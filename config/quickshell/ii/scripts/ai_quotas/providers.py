"""Bounded read-only clients. No browser scraping, inference or token refresh code."""
from __future__ import annotations

import base64
import binascii
from contextlib import contextmanager
from datetime import datetime, timezone
import hashlib
import json
import math
import os
from pathlib import Path
import re
import selectors
import shutil
import signal
import subprocess
import tempfile
import time
import urllib.error
import urllib.request

from .accounts import MAX_BYTES, QuotaError


def number(value, *, maximum: float | None = None) -> float | None:
    if type(value) not in (int, float) or not math.isfinite(value) or value < 0:
        return None
    return float(value) if maximum is None or value <= maximum else None


def timestamp(value) -> str | None:
    if value is None:
        return None
    try:
        if isinstance(value, str) and not value.isdigit():
            date = datetime.fromisoformat(value.replace("Z", "+00:00"))
            if date.tzinfo is None:
                return None
        else:
            seconds = float(value)
            if seconds > 100_000_000_000:
                seconds /= 1000
            date = datetime.fromtimestamp(seconds, timezone.utc)
        return date.astimezone(timezone.utc).isoformat()
    except (ValueError, TypeError, OverflowError, OSError):
        return None


def label(value: str) -> str:
    return " ".join(str(value).split())[:100]


def window(name: str, used=None, reset=None, *, amount=None, limit=None, reset_text=None) -> dict:
    # resetsAt is the only reset instant exposed. The UI derives a relative
    # countdown from it; no preformatted date or timezone is ever produced here.
    return {"label": label(name), "usedPercent": number(used, maximum=100), "resetsAt": timestamp(reset),
            "usedAmount": number(amount), "limitAmount": number(limit),
            "resetText": label(reset_text) if reset_text else None}


def identity(provider: str, principal) -> str | None:
    if not isinstance(principal, (str, int)) or isinstance(principal, bool) or not str(principal):
        return None
    return hashlib.sha256(f"{provider}:{principal}".encode()).hexdigest()


def result(windows: list[dict], *, principal: str | None = None, plan: str | None = None) -> dict:
    if not windows or len(windows) > 32:
        raise QuotaError("unsupported-response")
    return {"windows": windows, "identity": principal, "identityVerified": principal is not None,
            "plan": label(plan) if plan else None}


def parse_opencode(data: dict) -> dict:
    usage = data.get("usage")
    if not isinstance(usage, dict):
        raise QuotaError("unsupported-response")
    windows = []
    for key, name in (("rolling", "5 h"), ("weekly", "Semanal"), ("monthly", "Mensual")):
        entry = usage.get(key)
        if isinstance(entry, dict) and "percent" in entry:
            windows.append(window(name, entry["percent"], entry.get("resetsAt")))
    # The usage payload does not prove a principal/workspace identity.
    return result(windows)


def parse_codex(data: dict) -> dict:
    snapshots = data.get("rateLimitsByLimitId")
    if not isinstance(snapshots, dict) or not snapshots:
        snapshots = {"codex": data.get("rateLimits")}
    windows = []
    for bucket_id, snapshot in snapshots.items():
        if not isinstance(snapshot, dict):
            continue
        for key in ("primary", "secondary"):
            entry = snapshot.get(key)
            if not isinstance(entry, dict):
                continue
            duration = entry.get("windowDurationMins")
            name = "5 h" if duration == 300 else "Semanal" if duration == 10080 else (
                f"{duration} min" if type(duration) is int and duration > 0 else "Ventana sin duración")
            if len(snapshots) > 1:
                name = f"{label(bucket_id)} · {name}"
            windows.append(window(name, entry.get("usedPercent"), entry.get("resetsAt")))
    return result(windows, principal=identity("codex", data.get("accountId")))


def parse_antigravity(data: dict) -> dict:
    data = data.get("result", {}) if data.get("event") == "result" else data
    if not isinstance(data, dict) or data.get("status") not in ("SUCCESS", "OK"):
        raise QuotaError("unsupported-response")
    command = data.get("command", {})
    if not isinstance(command, dict) or command.get("name") != "usage":
        raise QuotaError("unsupported-response")
    payload = command.get("data")
    if not isinstance(payload, dict) or not isinstance(payload.get("groups"), list):
        raise QuotaError("unsupported-response")
    windows = []
    for group in payload["groups"][:8]:
        if not isinstance(group, dict) or not isinstance(group.get("buckets"), list):
            raise QuotaError("unsupported-response")
        group_name = group.get("name", "Antigravity")
        for bucket in group["buckets"][:8]:
            if not isinstance(bucket, dict) or bucket.get("enabled") is False:
                continue
            cadence = bucket.get("window")
            # The weekly Gemini Models bucket duplicates the 5 h one; keep only
            # the 5 h bucket and drop the redundant weekly reading.
            if group_name == "Gemini Models" and cadence == "weekly":
                continue
            fraction = number(bucket.get("remaining_fraction", bucket.get("remainingFraction")), maximum=1)
            name = "5 h" if cadence == "5h" else "Semanal" if cadence == "weekly" else bucket.get("name", "Cuota")
            windows.append(window(f"{group_name} · {name}",
                                  (1 - fraction) * 100 if fraction is not None else None,
                                  bucket.get("reset_time", bucket.get("resetTime")),
                                  reset_text=bucket.get("description")))
    # The Argon bucket is promoted to the first slot. Stable sort keeps the rest
    # in the provider's reported order.
    windows.sort(key=lambda entry: 0 if "Argon" in entry["label"] else 1)
    # No verified account identity in the native usage report. Never infer it.
    return result(windows)


def parse_cursor(data: dict) -> dict:
    individual = data.get("individualUsage")
    if not isinstance(individual, dict) or not isinstance(individual.get("plan"), dict):
        raise QuotaError("unsupported-response")
    plan, windows = individual["plan"], []
    # The plan total is intentionally not shown; only the per-model bars are.
    for field, name in (("autoPercentUsed", "Modelos de Cursor"), ("apiPercentUsed", "Otros modelos")):
        if field in plan:
            windows.append(window(name, plan[field], data.get("billingCycleEnd")))
    if not windows and plan.get("enabled") is True:
        used, limit = number(plan.get("used")), number(plan.get("limit"))
        windows.append(window("Crédito del plan", used / limit * 100 if used is not None and limit else None,
                              data.get("billingCycleEnd"), amount=used / 100 if used is not None else None,
                              limit=limit / 100 if limit is not None else None))
    return result(windows, plan=data.get("membershipType"))


def parse_zed(data: dict) -> dict:
    usage = data.get("current_usage")
    if not isinstance(usage, dict) or not isinstance(usage.get("token_spend"), dict):
        raise QuotaError("unsupported-response")
    spend = usage["token_spend"]
    used, limit = number(spend.get("spend_in_cents")), number(spend.get("limit_in_cents"))
    # This is the reported spending budget, not an invented included-credit balance.
    return result([window("Presupuesto de tokens (USD)",
                          used / limit * 100 if used is not None and limit and used <= limit else None,
                          amount=used / 100 if used is not None else None,
                           limit=limit / 100 if limit is not None else None)], plan=data.get("plan"))


def parse_claude(data: dict) -> dict:
    windows = []
    for key, name in (("five_hour", "5 h"), ("seven_day", "Semanal"),
                      ("seven_day_sonnet", "Sonnet · semanal"), ("seven_day_opus", "Opus · semanal")):
        entry = data.get(key)
        if isinstance(entry, dict) and number(entry.get("utilization"), maximum=100) is not None:
            windows.append(window(name, entry["utilization"], entry.get("resets_at")))
    # Subscription OAuth usage, never developer API billing or an inferred plan limit.
    return result(windows)


# Grok Bot (Anysphere/Cursor desktop app) persists its weekly usage reading in a
# local key/value store. Each entry is one base32-named blob; only the small
# "weekly-usage.cache" entry is read, never conversation transcripts.
GROKBOT_STATE = Path("Grok Bot/sand-client-persistence")
# The usage entry is tiny; a generous bound rejects any other blob outright.
GROKBOT_MAX_BLOB = 64 * 1024


def grokbot_directory() -> Path:
    return Path(os.environ.get("XDG_CONFIG_HOME", str(Path.home() / ".config"))) / GROKBOT_STATE


def grokbot_cache_files(directory: Path | None = None) -> list[Path]:
    directory = directory or grokbot_directory()
    try:
        names = os.listdir(directory)
    except OSError:
        return []
    found = []
    for name in sorted(names):
        if not name.endswith(".blob"):
            continue
        stem = name[:-5]
        try:
            key = base64.b32decode(stem.upper() + "=" * (-len(stem) % 8))
        except (ValueError, binascii.Error):
            continue
        if key.endswith(b".weekly-usage.cache"):
            found.append(directory / name)
    return found


def grokbot_available() -> bool:
    return bool(grokbot_cache_files())


def parse_grokbot(usage: dict) -> dict:
    percent = number(usage.get("percentUsed"), maximum=100)
    plan = usage.get("grokPlanLabel")
    # One weekly window, exactly what the app itself shows.
    return result([window("Semanal", percent, usage.get("nextResetMs"))],
                  plan=plan if isinstance(plan, str) and plan else None)


def grokbot_reading(directory: Path | None = None, files: list[Path] | None = None) -> dict | None:
    best = None
    for path in files if files is not None else grokbot_cache_files(directory):
        try:
            if path.stat().st_size > GROKBOT_MAX_BLOB:
                continue
            data = json.loads(path.read_bytes())
        except (OSError, ValueError, UnicodeError):
            continue
        if not isinstance(data, dict):
            continue
        value = data.get("value")
        reading = value.get("reading") if isinstance(value, dict) else None
        usage = reading.get("usage") if isinstance(reading, dict) else None
        if not isinstance(usage, dict) or number(usage.get("percentUsed"), maximum=100) is None:
            continue
        read_at = reading.get("readAtMs") if isinstance(reading, dict) else None
        if best is None or (isinstance(read_at, (int, float)) and read_at > best[0]):
            best = (read_at if isinstance(read_at, (int, float)) else 0, usage)
    return best[1] if best else None


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise QuotaError("redirect-rejected")


def http_json(url: str, headers: dict, *, expired_code: str = "auth-expired") -> dict:
    # URLs are constants in adapters; no caller-controlled origins or redirect forwarding.
    opener = urllib.request.build_opener(NoRedirect())
    request = urllib.request.Request(url, headers={"Accept": "application/json", **headers})
    try:
        with opener.open(request, timeout=12) as response:
            raw = response.read(MAX_BYTES + 1)
    except urllib.error.HTTPError as error:
        if error.code in (401, 403):
            raise QuotaError(expired_code) from None
        delay = error.headers.get("Retry-After", "0")
        raise QuotaError("rate-limited" if error.code == 429 else "provider-error",
                         int(delay) if delay.isdigit() else 0) from None
    except (urllib.error.URLError, TimeoutError, OSError):
        raise QuotaError("network-error") from None
    if len(raw) > MAX_BYTES:
        raise QuotaError("response-too-large")
    return decode_json(raw)


def decode_json(raw: bytes) -> dict:
    try:
        data = json.loads(raw)
    except (ValueError, UnicodeError):
        raise QuotaError("unsupported-response") from None
    if not isinstance(data, dict):
        raise QuotaError("unsupported-response")
    return data


class ClientProcess:
    """Owned process group, bounded stdout/stderr, deadline, no raw diagnostics."""

    def __init__(self, args: list[str], cwd: Path, environment: dict, timeout: int = 25):
        self.process = subprocess.Popen(args, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                        stderr=subprocess.PIPE, cwd=cwd, env=environment, start_new_session=True)
        assert self.process.stdin is not None and self.process.stdout is not None and self.process.stderr is not None
        self.stdin, self.stdout, self.stderr = self.process.stdin, self.process.stdout, self.process.stderr
        self.deadline = time.monotonic() + timeout
        self.selector = selectors.DefaultSelector()
        self.selector.register(self.stdout.fileno(), selectors.EVENT_READ, "out")
        self.selector.register(self.stderr.fileno(), selectors.EVENT_READ, "err")
        self.pending = b""
        self.consumed = 0

    def send(self, value: dict) -> None:
        try:
            self.stdin.write(json.dumps(value).encode() + b"\n")
            self.stdin.flush()
        except (BrokenPipeError, OSError):
            raise QuotaError("client-failed") from None

    def read_chunk(self) -> bytes:
        remaining = self.deadline - time.monotonic()
        if remaining <= 0:
            raise QuotaError("client-timeout")
        events = self.selector.select(min(remaining, .5))
        for key, _ in events:
            raw = os.read(key.fd, 65536)
            if not raw:
                self.selector.unregister(key.fileobj)
                continue
            self.consumed += len(raw)
            if self.consumed > MAX_BYTES:
                raise QuotaError("response-too-large")
            if key.data == "out":
                return raw
        return b""

    def rpc(self, request_id: int, method: str, params=None) -> dict:
        request = {"id": request_id, "method": method}
        if params is not None:
            request["params"] = params
        self.send(request)
        while self.selector.get_map():
            while b"\n" in self.pending:
                line, self.pending = self.pending.split(b"\n", 1)
                data = decode_json(line)
                if data.get("id") == request_id:
                    if "error" in data or not isinstance(data.get("result"), dict):
                        raise QuotaError("auth-or-client-error")
                    return data["result"]
            self.pending += self.read_chunk()
        raise QuotaError("client-failed")

    def collect(self) -> bytes:
        data = b""
        while self.selector.get_map():
            data += self.read_chunk()
        if self.process.wait(timeout=1) != 0:
            raise QuotaError("auth-or-client-error")
        return data

    def close(self) -> None:
        try:
            os.killpg(self.process.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            self.process.wait(timeout=1)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(self.process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            self.process.wait(timeout=2)
        self.selector.close()
        for stream in (self.stdin, self.stdout, self.stderr):
            stream.close()


@contextmanager
def native_client(args: list[str], *, timeout: int = 25):
    executable = shutil.which(args[0])
    if not executable:
        raise QuotaError("dependency-missing")
    # An expired login must not launch a browser during a background usage poll.
    with tempfile.TemporaryDirectory(prefix="ai-quota-client-") as directory:
        root = Path(directory)
        for name in ("open", "xdg-open"):
            blocker = root / name
            blocker.write_text("#!/bin/sh\nexit 1\n", encoding="utf-8")
            blocker.chmod(0o700)
        environment = {**os.environ, "PATH": str(root) + os.pathsep + os.environ.get("PATH", ""),
                       "BROWSER": str(root / "xdg-open"), "AGY_CLI_DISABLE_AUTO_UPDATE": "true",
                       "DISABLE_AUTOUPDATER": "1"}
        # Do not forward ad-hoc model API credentials into the quota subprocess.
        for key in tuple(environment):
            if key.endswith(("_API_KEY", "_ACCESS_TOKEN", "_REFRESH_TOKEN")):
                environment.pop(key)
        environment.pop("OPENCODE_AUTH_CONTENT", None)
        process = ClientProcess([executable, *args[1:]], root, environment, timeout=timeout)
        try:
            yield process
        finally:
            process.close()


def fetch_codex() -> dict:
    with native_client(["codex", "-s", "read-only", "-a", "never", "app-server"]) as client:
        client.rpc(1, "initialize", {"clientInfo": {"name": "dots_quota", "version": "1.0.0"}})
        client.send({"method": "initialized"})
        before = client.rpc(2, "account/read", {"refreshToken": False}).get("account")
        if not isinstance(before, dict) or before.get("type") != "chatgpt":
            raise QuotaError("chatgpt-login-required")
        data = client.rpc(3, "account/rateLimits/read")
        after = client.rpc(4, "account/read", {"refreshToken": False}).get("account")
        if before != after:
            raise QuotaError("account-changed")
        return parse_codex(data)


def antigravity_version(executable: str = "agy") -> None:
    with native_client([executable, "--version"]) as client:
        version = client.collect().decode("utf-8", errors="replace")
    match = re.fullmatch(r"\s*(?:(?:agy|Antigravity CLI)(?: version)?\s+)?v?(\d+)\.(\d+)\.(\d+)(?:[-+][\w.-]+)?\s*", version)
    if not match or tuple(map(int, match.groups())) < (1, 1, 11):
        # Older versions may treat /usage as a model prompt. Never try them.
        raise QuotaError("unsupported-client-version")


def fetch_antigravity() -> dict:
    from .guided import client_path
    executable = client_path("agy") or "agy"
    antigravity_version(executable)
    with native_client([executable, "-p", "/usage", "--output-format", "json"]) as client:
        return parse_antigravity(decode_json(client.collect()))


def validate_secret(source: str, secret: str) -> str:
    if not isinstance(secret, str) or not secret or len(secret) > 16384 or any(ord(c) < 33 or ord(c) > 126 for c in secret):
        raise QuotaError("invalid-credential")
    if source.endswith("-cookie"):
        prefix = "zed.session=" if source == "zed-cookie" else "WorkosCursorSessionToken="
        if ";" in secret or secret.lower().startswith((prefix.lower(), "cookie:")):
            raise QuotaError("invalid-credential")
    if source == "claude-oauth" and not secret.startswith("sk-ant-oat01-"):
        raise QuotaError("invalid-credential")
    return secret


def fetch(account: dict, vault) -> dict:
    source = account["source"]
    if source == "opencode-bridge":
        from .bridge import run
        return run(account["provider"])
    if source == "browser-session":
        from .bridge import run
        return run(account["provider"])
    if source == "browser-extension":
        from .browser_link import fetch as fetch_browser_link
        return fetch_browser_link(account)
    if source == "claude-statusline":
        from .claude_statusline import fetch as fetch_statusline
        return fetch_statusline()
    if source == "grokbot-cache":
        reading = grokbot_reading()
        if reading is None:
            raise QuotaError("dependency-missing")
        return parse_grokbot(reading)
    if source == "codex-cli":
        return fetch_codex()
    if source == "agy-cli":
        return fetch_antigravity()
    secret = validate_secret(source, vault.get(account["provider"], account["credential"]))
    if source == "api-key":
        return parse_opencode(http_json("https://opencode.ai/zen/go/v1/usage", {"Authorization": "Bearer " + secret}))
    if source == "claude-oauth":
        return parse_claude(http_json("https://api.anthropic.com/api/oauth/usage", {
            "Authorization": "Bearer " + secret, "anthropic-beta": "oauth-2025-04-20"}))
    if source == "cursor-cookie":
        headers = {"Cookie": "WorkosCursorSessionToken=" + secret}
        before = http_json("https://cursor.com/api/auth/me", headers, expired_code="session-cookie-expired")
        principal = before.get("id", before.get("userId", before.get("sub")))
        if principal is None:
            raise QuotaError("identity-unavailable")
        data = http_json("https://cursor.com/api/usage-summary", headers, expired_code="session-cookie-expired")
        after = http_json("https://cursor.com/api/auth/me", headers, expired_code="session-cookie-expired")
        if after.get("id", after.get("userId", after.get("sub"))) != principal:
            raise QuotaError("account-changed")
        parsed = parse_cursor(data)
        parsed.update(identity=identity("cursor", principal), identityVerified=True)
        return parsed
    if source == "zed-cookie":
        return parse_zed(http_json("https://cloud.zed.dev/frontend/billing/usage",
            {"Cookie": "zed.session=" + secret}, expired_code="session-cookie-expired"))
    raise QuotaError("unsupported-source")
