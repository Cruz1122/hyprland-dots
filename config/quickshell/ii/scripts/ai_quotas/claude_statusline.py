"""Consume the official Claude Code statusline contract, never its credentials."""
from __future__ import annotations

import json
import os
from pathlib import Path
import shlex
import stat
import subprocess
import sys
import time

from .accounts import QuotaError, private_directory, read_json, write_json, file_lock
from . import providers


def root_path() -> Path:
    return private_directory(Path(os.environ.get("XDG_STATE_HOME", str(Path.home() / ".local/state")))
                             / "illogical-impulse/ai-quotas")


def command_line() -> str:
    return shlex.join(["/usr/bin/python3", "-B", str(Path(__file__).resolve().parents[1] / "claude-statusline.py")])


def read_settings(path: Path) -> tuple[dict, bytes]:
    """Claude settings may legitimately be 0644; still require ownership and no symlink."""
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    except FileNotFoundError:
        return {}, b""
    with os.fdopen(fd, "rb") as stream:
        info = os.fstat(stream.fileno())
        if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_size > 1024 * 1024:
            raise QuotaError("unsafe-storage")
        before = stream.read(1024 * 1024 + 1)
    try:
        data = json.loads(before) if before else {}
    except ValueError:
        raise QuotaError("invalid-storage") from None
    if not isinstance(data, dict):
        raise QuotaError("invalid-storage")
    return data, before


def parse(data: dict) -> dict:
    rate = data.get("rate_limits")
    if not isinstance(rate, dict):
        raise QuotaError("waiting-usage")
    windows = []
    for key, name in (("five_hour", "5 h"), ("seven_day", "Semanal")):
        entry = rate.get(key)
        if not isinstance(entry, dict):
            continue
        used = providers.number(entry.get("used_percentage"))
        reset = providers.number(entry.get("resets_at"))
        if used is not None and reset is not None and reset > time.time():
            windows.append(providers.window(name, min(used, 100), reset,
                amount=used if used > 100 else None, limit=100 if used > 100 else None))
    if not windows:
        raise QuotaError("waiting-usage")
    return providers.result(windows)


def configure() -> None:
    directory = Path(os.environ.get("CLAUDE_CONFIG_DIR", str(Path.home() / ".claude")))
    if directory.is_symlink():
        raise QuotaError("unsafe-storage")
    directory.mkdir(mode=0o700, parents=True, exist_ok=True)
    path = directory / "settings.json"
    command = command_line()
    state = root_path()
    with file_lock(state / "claude-statusline.lock"):
        data, before = read_settings(path)
        previous = data.get("statusLine")
        if isinstance(previous, dict) and previous.get("command") == command:
            return
        if previous is not None and (not isinstance(previous, dict) or previous.get("type") != "command"
                                      or not isinstance(previous.get("command"), str)):
            raise QuotaError("statusline-conflict")
        if previous and "claude-statusline.py" in previous["command"]:
            # Never chain a relocated copy of this wrapper back into itself.
            raise QuotaError("statusline-conflict")
        # Only the old statusline is backed up, never unrelated configuration/API keys.
        write_json(state / "claude-statusline.previous.json", {"statusLine": previous})
        # Compare before atomic replacement; never overwrite a concurrent settings edit.
        if (path.read_bytes() if path.exists() else b"") != before:
            raise QuotaError("account-changed")
        data["statusLine"] = {**(previous or {}), "type": "command", "command": command}
        write_json(path, data)


def unconfigure() -> None:
    directory = Path(os.environ.get("CLAUDE_CONFIG_DIR", str(Path.home() / ".claude")))
    path = directory / "settings.json"
    if directory.is_symlink() or path.is_symlink():
        raise QuotaError("unsafe-storage")
    if not path.exists():
        return
    state = root_path()
    with file_lock(state / "claude-statusline.lock"):
        # Other tools may rewrite this file with 0644 after setup. Apply the same
        # ownership/type checks as configure(), not private-cache-only mode checks.
        data, before = read_settings(path)
        current = data.get("statusLine")
        if not isinstance(current, dict) or current.get("command") != command_line():
            return
        previous = read_json(state / "claude-statusline.previous.json", {}).get("statusLine")
        if previous is None:
            data.pop("statusLine", None)
        else:
            data["statusLine"] = previous
        if path.read_bytes() != before:
            raise QuotaError("account-changed")
        write_json(path, data)
        (state / "claude-statusline.json").unlink(missing_ok=True)


def fetch() -> dict:
    data = read_json(root_path() / "claude-statusline.json", {})
    observed = providers.number(data.get("observedAt"))
    if observed is None or not 0 <= time.time() - observed <= 900:
        raise QuotaError("waiting-usage")
    result = parse({"rate_limits": data.get("rate_limits")})
    result["observedAt"] = observed
    return result


def capture() -> int:
    raw = sys.stdin.buffer.read(1024 * 1024 + 1)
    if len(raw) > 1024 * 1024:
        return 1
    try:
        data = json.loads(raw)
        if not isinstance(data, dict):
            return 1
        # Whitelist only official rate-limit numbers. Never persist cwd, transcript,
        # model prompts, session IDs, arbitrary payloads or credentials.
        raw_rate = data.get("rate_limits")
        rate = raw_rate if isinstance(raw_rate, dict) else {}
        clean = {}
        for key in ("five_hour", "seven_day"):
            entry = rate.get(key)
            if isinstance(entry, dict):
                used = providers.number(entry.get("used_percentage"))
                reset = providers.number(entry.get("resets_at"))
                if used is not None and reset is not None:
                    clean[key] = {"used_percentage": used, "resets_at": reset}
        state = root_path()
        write_json(state / "claude-statusline.json", {"observedAt": time.time(), "rate_limits": clean})
        previous = read_json(state / "claude-statusline.previous.json", {}).get("statusLine")
        if isinstance(previous, dict) and isinstance(previous.get("command"), str):
            # This is the user's existing trusted statusline command, not provider input.
            return subprocess.run(["/bin/sh", "-c", previous["command"]], input=raw,
                                  timeout=3, stderr=subprocess.DEVNULL).returncode
        print("Claude · " + " · ".join(f"{name}: {value['used_percentage']:g}%" for name, value in clean.items()))
        return 0
    except (ValueError, OSError, QuotaError, subprocess.TimeoutExpired):
        return 1
