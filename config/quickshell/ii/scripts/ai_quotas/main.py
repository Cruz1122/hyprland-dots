"""Single-flight quota polling with a GUI-driven account manager."""
from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor
import json
import os
from pathlib import Path
import queue
import random
import shutil
import sys
import threading
import time
import uuid

from .accounts import (Accounts, PROVIDERS, QuotaError, Vault, clean_label, file_lock, managed_source,
                       private_directory, read_json, write_json)
from . import providers


MESSAGES = {
    "unconfigured": "Configura una cuenta en Ajustes → Servicios → Cuotas de IA.",
    "not-subscribed": "Sin suscripción configurada.",
    "disabled": "Actualización desactivada. Selecciona una cuenta para activarla.",
    "loading": "Consultando la cuota…",
    "dependency-missing": "Falta el cliente oficial en PATH. No se ha instalado nada.",
    "bridge-missing": "No se encuentra el puente de tu fork en ~/dev/opencode. Configura OPENCODE_QUOTA_ROOT si lo moviste.",
    "cancelled": "Conexión cancelada.",
    "browser-missing": "Necesitas Brave, Chromium o Google Chrome para conectar esta cuenta.",
    "browser-failed": "No se pudo abrir la sesión privada del panel. Cierra su ventana e inténtalo de nuevo.",
    "login-timeout": "No se completó el inicio de sesión. Pulsa Conectar para continuar.",
    "waiting-usage": "Esperando límites de Claude Code. Aparecerán después de tu primera respuesta con Pro/Max; el panel no envía mensajes.",
    "waiting-browser-usage": "Esperando los límites desde tu navegador habitual. Comprueba que el enlace del panel esté activo.",
    "browser-link-required": "Activa el enlace del panel en tu navegador habitual una vez. No necesitas copiar cookies ni iniciar sesión en otro perfil.",
    "session-cookie-expired": "Ese valor de sesión expiró o fue rechazado; un código de login no sirve como cookie. Evita seguir copiándolo: usa Conectar con navegador habitual.",
    "statusline-conflict": "La configuración de Claude Code usa una barra de estado no compatible. No se ha reemplazado.",
    "unsupported-platform": "La instalación guiada solo está disponible en Linux x86_64.",
    "download-failed": "No se pudo descargar el cliente oficial. No se ha ejecutado ningún instalador.",
    "checksum-mismatch": "La descarga no coincide con su hash verificado. Se descartó sin ejecutarla.",
    "unsupported-login-url": "El cliente devolvió una dirección de autorización no reconocida.",
    "consent-required": "Acepta la integración de uso antes de abrir su sesión privada.",
    "invalid-login-code": "Pega solo el código de autorización, sin URL ni otros datos.",
    "login-code-pending": "Ya hay un código pendiente de verificación…",
    "busy": "Ya hay una conexión en curso. Termínala o cancélala antes de abrir otra.",
    "secret-service-dependency": "Falta python-secretstorage para acceder al llavero de forma segura.",
    "locked": "Llavero bloqueado. Desbloquéalo desde el gestor del sistema.",
    "keyring-unavailable": "El servicio de secretos no está disponible.",
    "credential-missing": "Credencial no encontrada. Reconecta esta cuenta.",
    "auth-expired": "Sesión caducada o acceso denegado. Reconecta esta cuenta.",
    "chatgpt-login-required": "Inicia sesión en Codex con ChatGPT, no con una API key.",
    "auth-or-client-error": "El cliente no devolvió cuotas. Comprueba su sesión en el cliente oficial.",
    "unsupported-client-version": "La versión del cliente no permite consultar cuotas con seguridad.",
    "unsupported-response": "Formato de cuota no reconocido; no se han estimado valores.",
    "network-error": "Sin conexión con el proveedor.",
    "provider-error": "El proveedor no está disponible.",
    "rate-limited": "Demasiadas consultas. Se respetará el tiempo de espera.",
    "account-changed": "La cuenta cambió durante la consulta. Se descartó la respuesta.",
    "identity-unavailable": "El proveedor no permite verificar la identidad de esta sesión.",
    "client-timeout": "El cliente no respondió a tiempo.",
    "client-failed": "No se pudo ejecutar el cliente.",
    "response-too-large": "Respuesta fuera de los límites permitidos.",
    "invalid-credential": "Credencial inválida. Sustitúyela desde el gestor de cuentas.",
    "redirect-rejected": "Redirección del proveedor rechazada por seguridad.",
    "internal-error": "No se pudo consultar la cuota.",
}


class LazyVault:
    def get(self, provider: str, credential: str) -> str:
        return Vault().get(provider, credential)


class Controller:
    TTL = 180

    def __init__(self, accounts: Accounts, cache: Path | None = None, fetcher=providers.fetch):
        self.accounts = accounts
        self.cache = private_directory(cache or Path(os.environ.get("XDG_CACHE_HOME", str(Path.home() / ".cache")))
                                       / "illogical-impulse/ai-quotas")
        self.fetcher = fetcher

    def cache_path(self, account: dict, generation: int) -> Path:
        return self.cache / f"{account['id']}.{generation}.json"

    def purge_account(self, account_id: str) -> None:
        from .accounts import opaque_id
        opaque_id(account_id)
        for path in self.cache.glob(f"{account_id}.*.json"):
            path.unlink(missing_ok=True)

    @staticmethod
    def selected(data: dict, provider: str) -> dict | None:
        return next((a for a in data["accounts"] if a["provider"] == provider
                     and data["selected"].get(provider) == a["id"]), None)

    def current(self, data: dict, account: dict, generation: int) -> bool:
        selected = self.selected(data, account["provider"])
        return selected == account and data["generations"].get(account["provider"], 0) == generation

    def refresh(self, account: dict, generation: int, force: bool = False) -> None:
        try:
            # Cross-process single-flight: shell/settings/multiple monitors share this lock/cache.
            with file_lock(self.cache / f"{account['id']}.lock", blocking=False):
                if not self.current(self.accounts.read(), account, generation):
                    return
                path = self.cache_path(account, generation)
                for old in self.cache.glob(f"{account['id']}.*.json"):
                    if old != path:
                        old.unlink(missing_ok=True)
                previous = read_json(path, {})
                now = time.time()
                due = max(previous.get("attemptedAt", 0) + 30, previous.get("retryNotBefore", 0)) if force else previous.get("nextAttemptAt", 0)
                if now < due:
                    return
                try:
                    measurement = self.fetcher(account, LazyVault())
                    observed = measurement.pop("observedAt", time.time())
                    record = {"status": "ready", "observedAt": observed, "measurement": measurement,
                              "failures": 0, "attemptedAt": now,
                               "nextAttemptAt": time.time() + (5 if account["source"] in ("claude-statusline", "browser-extension") else self.TTL + random.randrange(16))}
                except Exception as error:
                    # Trust boundary: raw HTTP/CLI/DBus diagnostics may contain credentials.
                    code = error.code if isinstance(error, QuotaError) and error.code in MESSAGES else "internal-error"
                    failures = min(previous.get("failures", 0) + 1, 7)
                    delay = max(min(30 * 2 ** failures, 3600), getattr(error, "retry_after", 0))
                    if code in ("waiting-usage", "waiting-browser-usage"):
                        delay = 5
                    if code in ("auth-expired", "session-cookie-expired", "locked", "secret-service-dependency", "dependency-missing"):
                        delay = max(delay, 300)
                    record = {"status": code, "observedAt": None, "measurement": None,
                              "attemptedAt": now, "failures": failures,
                              "retryNotBefore": time.time() + delay,
                               "nextAttemptAt": time.time() + delay + (0 if code in ("waiting-usage", "waiting-browser-usage") else random.randrange(16))}
                # CAS publication, not just cancellation: late responses can never replace a new account.
                with self.accounts.locked() as latest:
                    if self.current(latest, account, generation):
                        write_json(path, {**record, "accountId": account["id"], "generation": generation,
                                          "source": account["source"], "credential": account["credential"]})
        except QuotaError as error:
            if error.code != "busy":
                raise

    def view(self) -> dict:
        from .guided import client_path
        data = self.accounts.read()
        snapshots = {}
        for provider, (name, _) in PROVIDERS.items():
            account = self.selected(data, provider)
            status = "not-subscribed" if provider == "claude" else "unconfigured"
            entry = {"provider": provider, "name": name, "status": status, "windows": [],
                     "observedAt": None, "identityVerified": False, "accountId": None,
                     "alias": "", "source": "", "sources": list(PROVIDERS[provider][1]),
                      "generation": data["generations"].get(provider, 0)}
            entry["requiresInstall"] = provider in ("antigravity", "claude") and not client_path(
                "agy" if provider == "antigravity" else "claude")
            if account:
                generation = entry["generation"]
                record = read_json(self.cache_path(account, generation), {})
                if (record.get("accountId") != account["id"] or record.get("generation") != generation
                        or record.get("source") != account["source"] or record.get("credential") != account["credential"]):
                    record = {}
                measurement = record.get("measurement") or {}
                observed = record.get("observedAt")
                # Never publish arbitrarily old values, even after a long suspended session.
                expired = observed is not None and time.time() - observed > 900
                status = "loading" if not record else record["status"]
                if expired:
                    measurement, status = {}, "loading"
                entry.update(status=status, accountId=account["id"], alias=account["alias"],
                             source=account["source"], observedAt=observed,
                             windows=measurement.get("windows", []), plan=measurement.get("plan"),
                             identityVerified=measurement.get("identityVerified", False),
                             stale=bool(observed and time.time() - observed > self.TTL))
            elif any(a["provider"] == provider for a in data["accounts"]):
                entry["status"] = "disabled"
            entry["message"] = MESSAGES.get(entry["status"], "")
            snapshots[provider] = entry
        return {"version": 1, "providers": snapshots,
                "accounts": [{k: a[k] for k in ("id", "provider", "alias", "source")} for a in data["accounts"]],
                "selected": data["selected"]}

    def poll(self, executor: ThreadPoolExecutor, pending: dict, blocked: set | None = None) -> None:
        data = self.accounts.read()
        for provider in PROVIDERS:
            if blocked and provider in blocked:
                continue
            account = self.selected(data, provider)
            if not account or provider in pending and not pending[provider].done():
                continue
            generation = data["generations"].get(provider, 0)
            record = read_json(self.cache_path(account, generation), {})
            if time.time() >= record.get("nextAttemptAt", 0):
                pending[provider] = executor.submit(self.refresh, account, generation)


def store_credential(provider: str, secret, source: str | None = None) -> str:
    """Validate and persist a user-provided secret, returning its opaque id.

    CLI sources (codex/antigravity) follow the official client session and store
    nothing here. Everything is driven by the GUI dialog; secrets are never
    echoed back over the command channel.
    """
    source = source or PROVIDERS[provider][1][0]
    if source not in PROVIDERS[provider][1]:
        raise QuotaError("unsupported-source")
    if source in ("browser-session", "browser-extension", "claude-statusline"):
        # These sources have no secret to stage in Secret Service; use guided setup.
        raise QuotaError("unsupported-source")
    if source == "opencode-bridge":
        from .bridge import run
        run(provider)
        return uuid.uuid4().hex
    if source.endswith("-cli"):
        if not shutil.which("codex" if provider == "codex" else "agy"):
            raise QuotaError("dependency-missing")
        return uuid.uuid4().hex
    value = providers.validate_secret(source, secret)

    class StagedVault:
        def get(self, *_):
            return value

    # Read-only check first so a bad credential never reaches the keyring.
    providers.fetch({"provider": provider, "source": source, "credential": uuid.uuid4().hex}, StagedVault())
    credential = uuid.uuid4().hex
    Vault().store(provider, credential, value)
    return credential


def add_account(accounts: Accounts, command: dict) -> None:
    provider = command.get("provider")
    if provider not in PROVIDERS or not PROVIDERS[provider][1]:
        raise QuotaError("unsupported-source")
    source = command.get("source") or PROVIDERS[provider][1][0]
    alias = clean_label(command.get("alias") or PROVIDERS[provider][0])
    credential = store_credential(provider, command.get("secret"), source)
    try:
        accounts.add(provider, source, alias, credential)
    except BaseException:
        if not managed_source(source):
            Vault().delete(provider, credential)
        raise


def reconnect_account(accounts: Accounts, command: dict) -> None:
    account_id = str(command.get("accountId") or "")
    account = next((a for a in accounts.read()["accounts"] if a["id"] == account_id), None)
    if not account:
        raise QuotaError("invalid-account")
    if managed_source(account["source"]):
        if account["source"] == "opencode-bridge":
            from .bridge import run
            run(account["provider"])
        accounts.mutate("invalidate", account_id)
        return
    new = store_credential(account["provider"], command.get("secret"), account["source"])
    try:
        accounts.replace_credential(account_id, account["credential"], new)
    except BaseException:
        Vault().delete(account["provider"], new)
        raise
    Vault().delete(account["provider"], account["credential"])


def remove_account(controller: "Controller", command: dict) -> None:
    account_id = str(command.get("accountId") or "")
    account = next((a for a in controller.accounts.read()["accounts"] if a["id"] == account_id), None)
    if not account:
        raise QuotaError("invalid-account")
    controller.accounts.mutate("invalidate", account_id)
    if account["source"] == "claude-statusline":
        from .claude_statusline import unconfigure
        unconfigure()
    if not managed_source(account["source"]):
        Vault().delete(account["provider"], account["credential"])
    controller.accounts.mutate("remove", account_id)
    controller.purge_account(account_id)


def ensure_builtin_accounts(accounts: Accounts) -> None:
    """Provision local, credential-free sources (Grok Bot cache) exactly once.

    Grok Bot has no login flow: its weekly reading is already on disk. Binding an
    account only makes the local file readable as a quota source, so it is
    created automatically when the app's cache exists.
    """
    try:
        if not providers.grokbot_available():
            return
        if any(account["provider"] == "grokbot" for account in accounts.read()["accounts"]):
            return
        accounts.add("grokbot", "grokbot-cache", "Grok Bot", uuid.uuid4().hex)
    except QuotaError:
        pass


def serve(controller: Controller) -> None:
    commands: queue.Queue = queue.Queue(maxsize=32)
    completions: queue.Queue = queue.Queue()
    jobs: dict = {}
    stopped = threading.Event()

    def connect(command: dict, cancelled: threading.Event, replies: queue.Queue) -> None:
        request_id = command["requestId"]
        try:
            # A headless refresh and a visible login must not fight for one browser profile.
            previous = pending.get(command["provider"])
            deadline = time.monotonic() + 30
            while previous and not previous.done():
                if cancelled.wait(.2):
                    raise QuotaError("cancelled")
                if time.monotonic() > deadline:
                    raise QuotaError("busy")
            if cancelled.is_set():
                raise QuotaError("cancelled")
            progress = lambda url: completions.put((request_id, "authorize", url))
            if command["_source"] == "browser-extension":
                from .browser_link import login
                command["_linkNonce"] = login(command["provider"], cancelled, progress,
                    status=lambda message: completions.put((request_id, "status", message)))
            elif command["_source"] in ("opencode-bridge", "browser-session"):
                from .bridge import run
                run(command["provider"], login=command["action"] == "login", cancelled=cancelled, progress=progress)
            else:
                from .guided import native_login
                if command["action"] in ("login", "install-login"):
                    native_login(command["provider"], cancelled, progress, install=command["action"] == "install-login", replies=replies)
                if command["_source"] == "claude-statusline":
                    from .claude_statusline import configure
                    if not cancelled.is_set():
                        configure()
                elif command["action"] == "add":
                    providers.fetch_antigravity()
            completions.put((request_id, "done", None))
        except Exception as error:
            code = error.code if isinstance(error, QuotaError) else "internal-error"
            completions.put((request_id, "error", {"code": code,
                "message": MESSAGES.get(code, MESSAGES["internal-error"])}))

    def read_commands():
        try:
            while True:
                raw = sys.stdin.buffer.readline(8193)
                if not raw:
                    break
                if len(raw) > 8192:
                    break
                try:
                    value = json.loads(raw)
                    if isinstance(value, dict):
                        commands.put_nowait(value)
                except (ValueError, queue.Full):
                    continue
        finally:
            stopped.set()

    threading.Thread(target=read_commands, daemon=True).start()
    pending, last, error_message, operation_result = {}, None, "", None
    with ThreadPoolExecutor(max_workers=3) as executor:
        while not stopped.is_set():
            try:
                batch, cancelled_ids = [], set()
                while not commands.empty():
                    incoming = commands.get_nowait()
                    request_id = incoming.get("requestId")
                    if incoming.get("action") == "cancel" and type(request_id) in (str, int):
                        cancelled_ids.add(request_id)
                        job = jobs.pop(request_id, None)
                        if job:
                            job[1].set()
                        operation_result = {"requestId": request_id, "ok": False, "message": MESSAGES["cancelled"]}
                    else:
                        batch.append(incoming)
                # Only this loop mutates accounts. A cancelled worker can never add one late.
                while not completions.empty():
                    request_id, stage, value = completions.get_nowait()
                    job = jobs.get(request_id)
                    if not job or job[1].is_set():
                        continue
                    command = job[0]
                    if stage == "authorize":
                        operation_result = {"requestId": request_id, "ok": True, "pending": True,
                                            "url": value, "browser": value is None,
                                            "requiresCode": command["provider"] in ("antigravity", "claude"),
                                            "message": "Completa la autorización en tu navegador…"}
                    elif stage == "status":
                        operation_result = {"requestId": request_id, "ok": True, "pending": True,
                                            "browser": True, "message": value}
                    else:
                        jobs.pop(request_id)
                        code = value.get("code") if isinstance(value, dict) else None
                        message = value.get("message", "") if isinstance(value, dict) else value or ""
                        if stage == "done":
                            try:
                                if controller.accounts.read()["generations"].get(command["provider"], 0) != command["_expectedGeneration"]:
                                    raise QuotaError("account-changed")
                                # One named account follows the active OpenCode session.
                                existing = next((a for a in controller.accounts.read()["accounts"]
                                                 if a["provider"] == command["provider"] and
                                                 a["source"] == command["_source"]), None)
                                if existing:
                                    controller.accounts.mutate("select", existing["id"])
                                else:
                                    controller.accounts.add(command["provider"], command["_source"],
                                         command["alias"], uuid.uuid4().hex)
                                if command["_source"] == "browser-extension":
                                    from .browser_link import bind
                                    bind(command["provider"], command["_linkNonce"])
                            except (QuotaError, OSError, ValueError, TypeError):
                                stage, message = "error", "No se pudo guardar la conexión."
                        operation_result = {"requestId": request_id, "ok": stage == "done", "message": message,
                                            **({"code": code} if code else {})}
                for command in batch:
                    action, provider = command.get("action"), command.get("provider")
                    request_id = command.get("requestId")
                    if type(request_id) in (str, int) and request_id in cancelled_ids:
                        continue
                    try:
                        if action == "prepare-browser":
                            from .browser_link import prepare
                            path = prepare(open_browser=False)
                            operation_result = {"requestId": request_id, "ok": True,
                                "setupPath": path, "message": "Activa Modo desarrollador → Cargar descomprimida y elige esta carpeta."}
                            continue
                        if action == "open-browser-manager":
                            from .browser_link import open_extension_manager
                            open_extension_manager()
                            operation_result = {"requestId": request_id, "ok": True, "message": ""}
                            continue
                        if action == "authorize-code":
                            from .guided import validate_login_code
                            if type(request_id) not in (str, int):
                                raise QuotaError("invalid-login-code")
                            job = jobs.get(request_id)
                            if not job or job[0]["_source"] not in ("agy-cli", "claude-statusline"):
                                raise QuotaError("invalid-login-code")
                            try:
                                job[2].put_nowait(validate_login_code(command.pop("code", None)))
                                operation_result = {"requestId": request_id, "ok": True, "pending": True,
                                    "requiresCode": False, "message": "Verificando la autorización…"}
                            except QuotaError:
                                operation_result = {"requestId": request_id, "ok": True, "pending": True,
                                    "requiresCode": True, "message": MESSAGES["invalid-login-code"]}
                            except queue.Full:
                                operation_result = {"requestId": request_id, "ok": True, "pending": True,
                                    "requiresCode": False, "message": MESSAGES["login-code-pending"]}
                            continue
                        if action == "cancel":
                            job = jobs.pop(request_id, None)
                            if job:
                                job[1].set()
                            continue
                        source = command.get("source") or (PROVIDERS[provider][1][0] if provider in PROVIDERS else "")
                        guided_sources = ("opencode-bridge", "browser-session", "browser-extension", "agy-cli", "claude-statusline")
                        if action in ("login", "install-login") or (action == "add" and source in guided_sources):
                            if (provider not in PROVIDERS or source not in PROVIDERS[provider][1]
                                    or source not in guided_sources or type(request_id) not in (str, int)
                                    or action == "install-login" and provider not in ("antigravity", "claude")
                                    or action == "login" and provider == "opencode"):
                                raise QuotaError("unsupported-source")
                            if source in ("browser-session", "browser-extension") and command.get("consent") is not True:
                                raise QuotaError("consent-required")
                            if jobs:
                                raise QuotaError("busy")
                            command["alias"] = clean_label(command.get("alias") or PROVIDERS[provider][0])
                            command["_source"] = source
                            command["_expectedGeneration"] = controller.accounts.read()["generations"].get(provider, 0)
                            cancelled = threading.Event()
                            replies: queue.Queue = queue.Queue(maxsize=1)
                            jobs[request_id] = (command, cancelled, replies)
                            executor.submit(connect, command, cancelled, replies)
                            operation_result = {"requestId": request_id, "ok": True, "pending": True,
                                                "message": "Instalando cliente oficial…" if action == "install-login"
                                                    else "Completa el inicio de sesión en la ventana que se abrirá…"}
                            continue
                        if action == "add":
                            add_account(controller.accounts, command)
                        elif action == "reconnect":
                            reconnect_account(controller.accounts, command)
                        elif action == "remove":
                            remove_account(controller, command)
                        elif action == "rename":
                            controller.accounts.mutate("rename", str(command.get("accountId") or ""),
                                                       alias=str(command.get("alias") or ""))
                        elif action in ("select", "disable"):
                            controller.accounts.mutate(action, str(command.get("accountId") or ""))
                        elif action == "refresh" and provider in PROVIDERS:
                            data = controller.accounts.read()
                            account = controller.selected(data, provider)
                            if account and not (provider in pending and not pending[provider].done()):
                                pending[provider] = executor.submit(controller.refresh, account,
                                                                   data["generations"].get(provider, 0), True)
                        if isinstance(request_id, (str, int)) and not isinstance(request_id, bool):
                            operation_result = {"requestId": request_id, "ok": True, "message": ""}
                    except (QuotaError, OSError, ValueError, TypeError) as error:
                        error_message = MESSAGES.get(getattr(error, "code", ""), "Operación no disponible.")
                        if isinstance(request_id, (str, int)) and not isinstance(request_id, bool):
                            operation_result = {"requestId": request_id, "ok": False,
                                                "message": error_message,
                                                **({"code": error.code} if isinstance(error, QuotaError) else {})}
                controller.poll(executor, pending, blocked={job[0]["provider"] for job in jobs.values()})
                output = controller.view()
                output["operationError"] = error_message
                output["operationResult"] = operation_result
                error_message = ""
            except (QuotaError, OSError, ValueError, TypeError) as error:
                error_message = MESSAGES.get(getattr(error, "code", ""), "Operación no disponible.")
                output = {"version": 1, "providers": {}, "accounts": [], "selected": {},
                          "operationError": error_message}
            encoded = json.dumps(output, ensure_ascii=True, allow_nan=False)
            if encoded != last:
                print(encoded, flush=True)
                last = encoded
            stopped.wait(1)
        for _, cancelled, _ in jobs.values():
            cancelled.set()


def main() -> int:
    parser = argparse.ArgumentParser(description="Private AI subscription quotas; secrets only travel over the serve channel.")
    parser.add_argument("action", choices=("serve", "view"))
    args = parser.parse_args()
    try:
        accounts = Accounts()
        ensure_builtin_accounts(accounts)
        if args.action == "serve":
            serve(Controller(accounts))
        else:
            print(json.dumps(Controller(accounts).view(), ensure_ascii=True))
    except (QuotaError, OSError, KeyboardInterrupt):
        print(json.dumps({"error": "unavailable"}))
        return 1
    return 0
