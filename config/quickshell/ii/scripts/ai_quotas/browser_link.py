"""Browser-native messaging: quota data only, no cookies, debug ports or auth stores."""
from __future__ import annotations

import json
import os
from pathlib import Path
import secrets
import shutil
import struct
import subprocess
import sys
import threading
import time

from .accounts import Accounts, QuotaError, private_directory, read_json, write_json, file_lock
from . import providers

HOST = "org.illogical_impulse.ai_quotas"
EXTENSION_ID = "iefgdhhgmoadbcheboeimkcboidogfee"
URLS = {"cursor": "https://cursor.com/dashboard", "zed": "https://dashboard.zed.dev/account"}
STATUSES = {"login-required": "Esperando que termines de iniciar sesión en la web…",
            "unavailable": "La web aún no entrega el uso. Se está reintentando…",
            "unsupported-response": "El proveedor cambió el formato de sus límites.",
            "account-changed": "La cuenta cambió durante la consulta."}


def root_path() -> Path:
    return private_directory(Path(os.environ.get("XDG_STATE_HOME", str(Path.home() / ".local/state")))
                             / "illogical-impulse/ai-quotas/browser-link")


def prepare(*, open_browser: bool = True) -> str:
    data = private_directory(Path(os.environ.get("XDG_DATA_HOME", str(Path.home() / ".local/share")))
                             / "illogical-impulse/ai-quotas/browser-link")
    extension = private_directory(data / "extension")
    scripts = Path(__file__).resolve().parents[1]
    source = scripts.parent / "browser-extension"
    for name in ("manifest.json", "background.mjs", "usage.mjs"):
        target = extension / name
        if target.is_symlink():
            raise QuotaError("unsafe-storage")
        target.write_bytes((source / name).read_bytes())
        target.chmod(0o600)
    launcher = data / "native-host"
    if launcher.is_symlink():
        raise QuotaError("unsafe-storage")
    launcher.write_text("#!/usr/bin/python3\nimport runpy,sys\n"
        f"sys.path.insert(0, {str(scripts)!r})\n"
        f"runpy.run_path({str(scripts / 'browser-quota-host.py')!r}, run_name='__main__')\n")
    launcher.chmod(0o700)
    config = Path(os.environ.get("XDG_CONFIG_HOME", str(Path.home() / ".config")))
    manifest = {"name": HOST, "description": "Private subscription quota data for the desktop panel",
        "path": str(launcher), "type": "stdio", "allowed_origins": [f"chrome-extension://{EXTENSION_ID}/"]}
    for browser in ("BraveSoftware/Brave-Browser", "chromium", "google-chrome"):
        directory = private_directory(config / browser / "NativeMessagingHosts")
        write_json(directory / (HOST + ".json"), manifest)
    if open_browser:
        open_extension_manager()
    return str(extension)


def open_extension_manager() -> None:
    for executable, url in (("brave", "brave://extensions/"), ("chromium", "chrome://extensions/"),
                            ("google-chrome-stable", "chrome://extensions/"), ("google-chrome", "chrome://extensions/")):
        binary = shutil.which(executable)
        if binary:
            subprocess.Popen([binary, url], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                             stderr=subprocess.DEVNULL, start_new_session=True)
            return
    raise QuotaError("browser-missing")


def selected() -> dict:
    data = Accounts().read()
    return {a["provider"]: {"accountId": a["id"], "generation": data["generations"].get(a["provider"], 0)}
            for a in data["accounts"] if a["source"] == "browser-extension"
            and data["selected"].get(a["provider"]) == a["id"]}


def ticket(provider: str, *, login: bool, account: dict | None = None) -> dict:
    return {"provider": provider, "nonce": secrets.token_hex(32), "expiresAt": time.time() + 180,
            "login": login, **(account or {})}


def state() -> dict:
    active = selected()
    root = root_path()
    with file_lock(root / "link.lock"):
        write_json(root / "heartbeat.json", {"observedAt": time.time()})
        # Canceled just-completed logins may leave sanitized result files behind.
        for path in root.glob("login-*.usage.json"):
            nonce = path.name.removeprefix("login-").removesuffix(".usage.json")
            if len(nonce) == 64 and all(c in "0123456789abcdef" for c in nonce) and time.time() - path.lstat().st_mtime > 900:
                path.unlink(missing_ok=True)
        requests = []
        for provider in URLS:
            current = read_json(root / (provider + ".ticket.json"), {})
            if current.get("expiresAt", 0) <= time.time():
                current = {}
            if current and not current.get("login") and active.get(provider) != {
                    "accountId": current.get("accountId"), "generation": current.get("generation")}:
                current = {}
            if not current and provider in active:
                previous = read_json(root / (provider + ".usage.json"), {})
                if (previous.get("accountId") != active[provider]["accountId"]
                        or previous.get("generation") != active[provider]["generation"]
                        or time.time() - previous.get("observedAt", 0) >= 180):
                    current = ticket(provider, login=False, account=active[provider])
                    write_json(root / (provider + ".ticket.json"), current)
            if current:
                requests.append({key: current[key] for key in ("provider", "nonce", "login")})
        return {"ok": True, "requests": requests}


def publish(command: dict) -> dict:
    provider, nonce = command.get("provider"), command.get("nonce")
    if provider not in URLS or not isinstance(nonce, str) or len(nonce) != 64:
        raise QuotaError("invalid-request")
    usage = command.get("usage")
    if not isinstance(usage, dict):
        raise QuotaError("unsupported-response")
    measurement = providers.parse_cursor(usage) if provider == "cursor" else providers.parse_zed(usage)
    if not any(window.get("usedPercent") is not None or window.get("usedAmount") is not None
               for window in measurement["windows"]):
        raise QuotaError("unsupported-response")
    identity = command.get("identity")
    if identity is not None and (provider != "cursor" or not isinstance(identity, str)
            or len(identity) != 64 or any(c not in "0123456789abcdef" for c in identity)):
        raise QuotaError("unsupported-response")
    measurement.update(identity=identity, identityVerified=bool(identity))
    active = selected()
    root = root_path()
    with file_lock(root / "link.lock"):
        path = root / (provider + ".ticket.json")
        current = read_json(path, {})
        if (current.get("nonce") != nonce or current.get("expiresAt", 0) <= time.time()
                or not current.get("login") and active.get(provider) != {
                    "accountId": current.get("accountId"), "generation": current.get("generation")}):
            raise QuotaError("account-changed")
        record = {"measurement": measurement, "observedAt": time.time(), "nonce": nonce,
                  "accountId": current.get("accountId"), "generation": current.get("generation")}
        destination = root / (("login-" + nonce) if current.get("login") else provider)
        write_json(destination.with_suffix(".usage.json"), record)
        path.unlink(missing_ok=True)  # Single-use ticket, never a reusable web callback.
    return {"ok": True}


def report(command: dict) -> dict:
    provider, nonce, code = command.get("provider"), command.get("nonce"), command.get("code")
    if provider not in URLS or not isinstance(code, str) or code not in STATUSES:
        raise QuotaError("invalid-request")
    root = root_path()
    with file_lock(root / "link.lock"):
        current = read_json(root / (provider + ".ticket.json"), {})
        if not isinstance(nonce, str) or current.get("nonce") != nonce or current.get("expiresAt", 0) <= time.time():
            raise QuotaError("account-changed")
        write_json(root / (provider + ".status.json"), {"nonce": nonce, "code": code})
    return {"ok": True}


def login(provider: str, cancelled: threading.Event, progress, status=None) -> str:
    if provider not in URLS:
        raise QuotaError("unsupported-source")
    root = root_path()
    heartbeat = read_json(root / "heartbeat.json", {})
    if not 0 <= time.time() - heartbeat.get("observedAt", 0) <= 120:
        raise QuotaError("browser-link-required")
    request = ticket(provider, login=True)
    nonce = request["nonce"]
    result_path = root / ("login-" + nonce + ".usage.json")
    with file_lock(root / "link.lock"):
        write_json(root / (provider + ".ticket.json"), request)
    progress(URLS[provider])  # Open normally, reusing the user's existing browser session.
    last_status = None
    try:
        while time.time() < request["expiresAt"]:
            if cancelled.wait(.25):
                raise QuotaError("cancelled")
            if result_path.exists():
                return nonce
            latest = read_json(root / (provider + ".status.json"), {})
            code = latest.get("code") if latest.get("nonce") == nonce else None
            if code in ("unsupported-response", "account-changed"):
                raise QuotaError(code)
            if code in STATUSES and code != last_status:
                if status:
                    status(STATUSES[code])
                last_status = code
        raise QuotaError("login-timeout")
    finally:
        with file_lock(root / "link.lock"):
            path = root / (provider + ".ticket.json")
            if read_json(path, {}).get("nonce") == nonce:
                path.unlink(missing_ok=True)
        if cancelled.is_set():
            result_path.unlink(missing_ok=True)


def bind(provider: str, nonce: str) -> None:
    current = selected().get(provider)
    if not current or len(nonce) != 64 or any(c not in "0123456789abcdef" for c in nonce):
        raise QuotaError("account-changed")
    root = root_path()
    with file_lock(root / "link.lock"):
        path = root / ("login-" + nonce + ".usage.json")
        record = read_json(path, {})
        if record.get("nonce") != nonce:
            raise QuotaError("account-changed")
        write_json(root / (provider + ".usage.json"), {**record, **current})
        path.unlink(missing_ok=True)


def fetch(account: dict) -> dict:
    record = read_json(root_path() / (account["provider"] + ".usage.json"), {})
    current = selected().get(account["provider"])
    observed = providers.number(record.get("observedAt"))
    if (not current or current["accountId"] != account["id"]
            or record.get("accountId") != current["accountId"] or record.get("generation") != current["generation"]
            or observed is None or not 0 <= time.time() - observed <= 900):
        raise QuotaError("waiting-browser-usage")
    return {**record["measurement"], "observedAt": observed}


def native_main() -> int:
    if len(sys.argv) < 2 or sys.argv[1] != f"chrome-extension://{EXTENSION_ID}/":
        return 1
    raw_size = sys.stdin.buffer.read(4)
    if len(raw_size) != 4:
        return 1
    size = struct.unpack("<I", raw_size)[0]
    if size > 1024 * 1024:
        return 1
    try:
        raw = sys.stdin.buffer.read(size)
        if len(raw) != size:
            return 1
        command = json.loads(raw)
        if not isinstance(command, dict):
            raise QuotaError("invalid-request")
        if command.get("action") == "state":
            result = state()
        elif command.get("action") == "publish":
            result = publish(command)
        elif command.get("action") == "report":
            result = report(command)
        else:
            raise QuotaError("invalid-request")
    except QuotaError as error:
        result = {"ok": False, "code": error.code if error.code in STATUSES else "unavailable"}
    except (ValueError, TypeError, OSError):
        result = {"ok": False, "code": "unavailable"}
    encoded = json.dumps(result, ensure_ascii=True, allow_nan=False).encode()
    sys.stdout.buffer.write(struct.pack("<I", len(encoded)) + encoded)
    sys.stdout.buffer.flush()
    return 0
