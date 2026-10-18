"""Explicit GUI setup for official clients; no OAuth credentials leave those clients."""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import platform
import pty
import queue
import re
import selectors
import shutil
import signal
import subprocess
import sys
import tarfile
import tempfile
import threading
import termios
import time
import urllib.request
from urllib.parse import urlsplit

from .accounts import QuotaError, private_directory, file_lock
from . import providers


# Explicit, reproducible downloads, not an installer script or a moving "latest" URL.
RELEASES = {
    "agy": ("1.4.2", "https://storage.googleapis.com/antigravity-public/antigravity-cli/"
            "1.4.2-4835981233356800/linux-x64/cli_linux_x64.tar.gz", "sha512",
            "4a393afc1369cee94e817c1b430c9128d02b12ebd4d5703ace5cd47b2333e216d673fb0097cbf7195f757b110163ba9850e9eea3fdbbaddd4b25668b82c03f05"),
    "claude": ("2.1.302", "https://downloads.claude.ai/claude-code-releases/2.1.302/linux-x64/claude", "sha256",
               "60d7eb7f12fbb28a52533fe8be5884097403562aa02dc73991a021c7067e29a5"),
}


def data_root() -> Path:
    return private_directory(Path(os.environ.get("XDG_DATA_HOME", str(Path.home() / ".local/share")))
                             / "illogical-impulse/ai-quotas/clients")


def client_path(name: str) -> str | None:
    if name not in RELEASES:
        raise QuotaError("unsupported-source")
    existing = shutil.which(name)
    if existing:
        return existing
    path = Path(os.environ.get("XDG_DATA_HOME", str(Path.home() / ".local/share"))) / "illogical-impulse/ai-quotas/clients" / name / RELEASES[name][0] / name
    if path.is_symlink():
        raise QuotaError("unsafe-storage")
    if path.is_file() and path.stat().st_uid == os.getuid() and os.access(path, os.X_OK):
        return str(path)
    return None


def check_cancelled(cancelled: threading.Event) -> None:
    if cancelled.is_set():
        raise QuotaError("cancelled")


def install_client(name: str, cancelled: threading.Event) -> str:
    existing = client_path(name)
    if existing:
        return existing
    if platform.system() != "Linux" or platform.machine() not in ("x86_64", "amd64"):
        raise QuotaError("unsupported-platform")
    version, url, algorithm, expected = RELEASES[name]
    root = private_directory(data_root() / name / version)
    with file_lock(root / "install.lock", blocking=False):
        check_cancelled(cancelled)
        with tempfile.TemporaryDirectory(dir=root, prefix="download-") as directory:
            archive = Path(directory) / "payload"
            digest = hashlib.new(algorithm)
            opener = urllib.request.build_opener(providers.NoRedirect())
            deadline, size = time.monotonic() + 120, 0
            try:
                with opener.open(url, timeout=12) as response, archive.open("wb") as stream:
                    while chunk := response.read(65536):
                        check_cancelled(cancelled)
                        size += len(chunk)
                        if size > 200 * 1024 * 1024 or time.monotonic() > deadline:
                            raise QuotaError("download-failed")
                        digest.update(chunk)
                        stream.write(chunk)
            except OSError:
                raise QuotaError("download-failed") from None
            if digest.hexdigest() != expected:
                raise QuotaError("checksum-mismatch")
            payload = Path(directory) / name
            if name == "agy":
                try:
                    with tarfile.open(archive, "r:gz") as bundle:
                        member = bundle.getmember("antigravity")
                        if not member.isfile() or member.size > 300 * 1024 * 1024:
                            raise QuotaError("download-failed")
                        source = bundle.extractfile(member)
                        if source is None:
                            raise QuotaError("download-failed")
                        with source, payload.open("wb") as target:
                            while chunk := source.read(65536):
                                check_cancelled(cancelled)
                                target.write(chunk)
                except (tarfile.TarError, KeyError):
                    raise QuotaError("download-failed") from None
            else:
                archive.rename(payload)
            check_cancelled(cancelled)
            payload.chmod(0o700)
            os.replace(payload, root / name)
    return str(root / name)


def login_url(value: str, provider: str) -> str:
    parsed = urlsplit(value)
    origins = {"antigravity": {"accounts.google.com"},
               "claude": {"claude.ai", "platform.claude.com", "console.anthropic.com"}}
    paths = {"antigravity": {"/o/oauth2/auth", "/o/oauth2/v2/auth"}, "claude": {"/oauth/authorize"}}
    if (len(value) > 8192 or parsed.scheme != "https" or parsed.netloc not in origins.get(provider, set())
            or parsed.fragment or parsed.path not in paths.get(provider, set()) or any(ord(c) < 32 for c in value)):
        raise QuotaError("unsupported-login-url")
    return value


def validate_login_code(value: object) -> str:
    if not isinstance(value, str):
        raise QuotaError("invalid-login-code")
    code = value.strip()
    if not re.fullmatch(r"[A-Za-z0-9._~/-]{8,2048}", code):
        raise QuotaError("invalid-login-code")
    return code


def native_login(provider: str, cancelled: threading.Event, progress, *, install: bool = False,
                 replies: queue.Queue | None = None) -> None:
    name = "agy" if provider == "antigravity" else "claude" if provider == "claude" else ""
    if not name:
        raise QuotaError("unsupported-source")
    executable = install_client(name, cancelled) if install else client_path(name)
    if not executable:
        raise QuotaError("dependency-missing")
    if name == "agy":
        # Never run /usage on a version which might interpret it as a model prompt.
        providers.antigravity_version(executable)
    with tempfile.TemporaryDirectory(prefix="quota-login-") as directory:
        root = Path(directory)
        launcher = root / "xdg-open"
        url_path = root / "authorization.json"
        launcher.write_text("#!/usr/bin/python3\nimport json, os, sys\n"
            "path = os.environ['QUOTA_LOGIN_URL_FILE']\n"
            "temporary = path + '.' + str(os.getpid())\n"
            "if os.path.exists(path): sys.exit(0)\n"
            "try:\n fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)\n"
            "except FileExistsError: sys.exit(0)\n"
            "with os.fdopen(fd, 'w') as stream: json.dump(sys.argv[-1], stream)\n"
            "os.replace(temporary, path)\n", encoding="utf-8")
        launcher.chmod(0o700)
        shutil.copyfile(launcher, root / "open")
        (root / "open").chmod(0o700)
        environment = {**os.environ, "BROWSER": str(launcher), "QUOTA_LOGIN_URL_FILE": str(url_path),
                       "PATH": str(root) + os.pathsep + os.environ.get("PATH", ""),
                       "AGY_CLI_DISABLE_AUTO_UPDATE": "true", "DISABLE_AUTOUPDATER": "1"}
        for key in tuple(environment):
            if key.endswith(("_API_KEY", "_ACCESS_TOKEN", "_REFRESH_TOKEN")):
                environment.pop(key)
        for key in ("CLAUDE_CODE_OAUTH_TOKEN", "ANTHROPIC_AUTH_TOKEN", "AGY_ADC_AUTH", "GOOGLE_APPLICATION_CREDENTIALS"):
            environment.pop(key, None)
        master, slave = pty.openpty()
        try:
            settings = termios.tcgetattr(slave)
            settings[3] &= ~(termios.ECHO | termios.ECHONL)
            termios.tcsetattr(slave, termios.TCSANOW, settings)
        except (OSError, termios.error):
            os.close(master)
            os.close(slave)
            raise
        args = [executable, "-p", "/usage", "--output-format", "json"] if name == "agy" else [executable, "auth", "login"]
        process = None
        selector = selectors.DefaultSelector()
        output = b""
        announced, consumed = False, 0
        diagnostic_tail = b""
        deadline = time.monotonic() + 180
        try:
            process = subprocess.Popen([sys.executable, str(Path(__file__).with_name("native_exec.py")), *args],
                stdin=slave, stdout=subprocess.PIPE, stderr=slave,
                cwd=root, env=environment, start_new_session=True)
            os.close(slave)
            slave = -1
            assert process.stdout is not None
            selector.register(master, selectors.EVENT_READ, "discard")
            selector.register(process.stdout, selectors.EVENT_READ, "output")
            while process.poll() is None or selector.get_map():
                check_cancelled(cancelled)
                if time.monotonic() > deadline:
                    raise QuotaError("client-timeout")
                if replies is not None:
                    try:
                        code = replies.get_nowait()
                    except queue.Empty:
                        pass
                    else:
                        # No shell, argv, file or result frame ever receives this secret.
                        os.write(master, (validate_login_code(code) + "\n").encode("ascii"))
                        del code
                if not announced and url_path.exists():
                    if url_path.stat().st_size > 16384:
                        raise QuotaError("unsupported-login-url")
                    url = json.loads(url_path.read_text())
                    if not isinstance(url, str):
                        raise QuotaError("unsupported-login-url")
                    progress(login_url(url, provider))
                    announced = True
                for key, _ in selector.select(.25):
                    try:
                        raw = os.read(key.fd, 65536)
                    except OSError:
                        raw = b""
                    if not raw:
                        selector.unregister(key.fileobj)
                        continue
                    consumed += len(raw)
                    if consumed > 1024 * 1024:
                        raise QuotaError("response-too-large")
                    if key.data == "output":
                        output += raw
                    if not announced:
                        diagnostic_tail = (diagnostic_tail + raw)[-16384:]
                        for match in re.finditer(r"https://[^\s\x1b<>\"']+(?=[\s\x1b<>\"'])", diagnostic_tail.decode("utf-8", errors="ignore")):
                            try:
                                url = login_url(match.group(0), provider)
                            except QuotaError:
                                continue
                            progress(url)
                            announced = True
                            break
            if process.wait(timeout=1) != 0:
                raise QuotaError("auth-or-client-error")
            if name == "agy":
                providers.parse_antigravity(providers.decode_json(output))
        finally:
            selector.close()
            if slave >= 0:
                os.close(slave)
            os.close(master)
            if process:
                try:
                    os.killpg(process.pid, signal.SIGTERM)
                except ProcessLookupError:
                    pass
                try:
                    process.wait(timeout=1)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait(timeout=2)
                if process.stdout:
                    process.stdout.close()
