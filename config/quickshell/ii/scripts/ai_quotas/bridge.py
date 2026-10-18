"""Private stdin/stdout bridge to the user's OpenCode fork; no credential copies."""
from __future__ import annotations

import os
from pathlib import Path
import threading
from urllib.parse import urlsplit

from .accounts import QuotaError
from . import providers


def command() -> list[str]:
    root = Path(os.environ.get("OPENCODE_QUOTA_ROOT", str(Path.home() / "dev/opencode")))
    script = root / "packages/opencode/script/quota-bridge.ts"
    if not root.is_absolute() or not script.is_file():
        raise QuotaError("bridge-missing")
    return ["bun", "run", str(script)]


def authorize_url(value, provider: str = "codex") -> str:
    if not isinstance(value, str) or len(value) > 4096:
        raise QuotaError("unsupported-response")
    url = urlsplit(value)
    if (url.scheme != "https" or url.netloc != "auth.openai.com"
            or url.path != "/oauth/authorize" or url.fragment):
        raise QuotaError("unsupported-response")
    return value


def measurement(frame: dict) -> dict:
    raw = frame.get("measurement")
    if not isinstance(raw, dict):
        raise QuotaError("unsupported-response")
    windows = []
    supplied = raw.get("windows")
    if supplied is not None:
        if not isinstance(supplied, list) or not 0 < len(supplied) <= 32:
            raise QuotaError("unsupported-response")
        for entry in supplied:
            if not isinstance(entry, dict) or not isinstance(entry.get("label"), str):
                raise QuotaError("unsupported-response")
            used = providers.number(entry.get("usedPercent"), maximum=100)
            amount = providers.number(entry.get("usedAmount"))
            limit = providers.number(entry.get("limitAmount"))
            if used is None and amount is None:
                raise QuotaError("unsupported-response")
            windows.append(providers.window(entry["label"], used, entry.get("resetsAt"), amount=amount, limit=limit))
    for key in ("primary", "secondary", "tertiary"):
        entry = raw.get(key)
        if entry is None:
            continue
        if not isinstance(entry, dict) or providers.number(entry.get("usedPercent"), maximum=100) is None:
            raise QuotaError("unsupported-response")
        duration = providers.number(entry.get("windowMinutes"))
        name = "5 h" if duration == 300 else "Semanal" if duration == 10080 else "Mensual" if duration == 43200 else "Ventana"
        windows.append(providers.window(name, entry["usedPercent"], entry.get("resetsAt")))
    principal = raw.get("identity")
    if principal is not None and (not isinstance(principal, str) or len(principal) != 64
                                  or any(c not in "0123456789abcdef" for c in principal)):
        raise QuotaError("unsupported-response")
    if raw.get("identityVerified") is not bool(principal):
        raise QuotaError("unsupported-response")
    return providers.result(windows, principal=principal)


def run(provider: str, *, login: bool = False, progress=None, cancelled: threading.Event | None = None) -> dict:
    if provider not in ("codex", "opencode", "cursor", "zed") or login and provider == "opencode":
        raise QuotaError("unsupported-source")
    with providers.native_client(command(), timeout=180 if login else 25) as client:
        client.send({"action": "login" if login else "usage", "provider": provider})
        authorized = False
        while True:
            if cancelled and cancelled.is_set():
                raise QuotaError("cancelled")
            if b"\n" not in client.pending:
                if not client.selector.get_map():
                    raise QuotaError("client-failed")
                client.pending += client.read_chunk()
                continue
            line, client.pending = client.pending.split(b"\n", 1)
            frame = providers.decode_json(line)
            if frame.get("version") != 1:
                raise QuotaError("unsupported-response")
            if frame.get("type") == "browser" and login and provider in ("cursor", "zed"):
                # The bridge owns the browser window; do not open a second browser.
                if progress:
                    progress(None)
                continue
            if frame.get("type") == "authorize" and login and not authorized:
                authorized = True
                url = authorize_url(frame.get("url"), provider)
                if progress:
                    progress(url)
                continue
            if frame.get("type") != "result":
                raise QuotaError("unsupported-response")
            if frame.get("ok") is not True:
                code = frame.get("code")
                allowed = {"invalid-request", "unsupported-source", "credential-missing", "auth-expired",
                           "chatgpt-login-required", "identity-unavailable", "account-changed", "network-error",
                           "provider-error", "rate-limited", "redirect-rejected", "unsupported-response",
                           "response-too-large", "invalid-credential", "client-failed", "client-timeout",
                           "browser-missing", "browser-failed", "login-timeout", "unsafe-storage", "busy"}
                raise QuotaError(code if isinstance(code, str) and code in allowed else "client-failed")
            return measurement(frame)
