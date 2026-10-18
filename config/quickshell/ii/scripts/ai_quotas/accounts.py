"""Private account metadata and an isolated, non-interactive Secret Service vault."""
from __future__ import annotations

from contextlib import contextmanager
import fcntl
import importlib
import json
import os
from pathlib import Path
import re
import stat
import tempfile
from typing import Iterator
import uuid


PROVIDERS = {
    "codex": ("Codex / ChatGPT", ("opencode-bridge", "codex-cli")),
    "opencode": ("OpenCode Go", ("opencode-bridge", "api-key")),
    "antigravity": ("Antigravity · Google AI Pro", ("agy-cli",)),
    "zed": ("Zed", ("browser-extension", "browser-session", "zed-cookie")),
    "cursor": ("Cursor", ("browser-extension", "browser-session", "cursor-cookie")),
    "claude": ("Claude", ("claude-statusline", "claude-oauth")),
    # Local read-only cache of the Grok Bot desktop app; no credential involved.
    "grokbot": ("Grok Bot", ("grokbot-cache",)),
}
APPLICATION = "illogical-impulse-ai-quotas"
MAX_BYTES = 1024 * 1024


def managed_source(source: object) -> bool:
    return isinstance(source, str) and (source.endswith("-cli") or source in ("opencode-bridge", "browser-session", "browser-extension", "claude-statusline"))


class QuotaError(Exception):
    """Only fixed, non-sensitive codes cross the process boundary."""

    def __init__(self, code: str, retry_after: int = 0):
        super().__init__(code)
        self.code = code
        self.retry_after = min(3600, max(0, retry_after))


def private_directory(path: Path) -> Path:
    path.mkdir(parents=True, mode=0o700, exist_ok=True)
    info = path.lstat()
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid():
        raise QuotaError("unsafe-storage")
    path.chmod(0o700)
    return path


def read_json(path: Path, default: dict) -> dict:
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    except FileNotFoundError:
        return default
    with os.fdopen(fd, "rb") as stream:
        info = os.fstat(stream.fileno())
        if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077:
            raise QuotaError("unsafe-storage")
        raw = stream.read(MAX_BYTES + 1)
    if len(raw) > MAX_BYTES:
        raise QuotaError("invalid-storage")
    try:
        result = json.loads(raw)
    except (ValueError, UnicodeError) as error:
        raise QuotaError("invalid-storage") from error
    if not isinstance(result, dict):
        raise QuotaError("invalid-storage")
    return result


def write_json(path: Path, data: dict) -> None:
    # Private directory + fresh temporary inode, never follow a destination link.
    fd, temporary = tempfile.mkstemp(prefix=".write-", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            json.dump(data, stream, ensure_ascii=True, allow_nan=False)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        Path(temporary).unlink(missing_ok=True)


@contextmanager
def file_lock(path: Path, *, blocking: bool = True) -> Iterator[None]:
    fd = os.open(path, os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW, 0o600)
    try:
        info = os.fstat(fd)
        if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077:
            raise QuotaError("unsafe-storage")
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | (0 if blocking else fcntl.LOCK_NB))
        except BlockingIOError as error:
            raise QuotaError("busy") from error
        yield
    finally:
        os.close(fd)


def opaque_id(value: object) -> str:
    if not isinstance(value, str) or not re.fullmatch(r"[a-f0-9]{32}", value):
        raise QuotaError("invalid-account")
    return value


def clean_label(value: str) -> str:
    value = " ".join(str(value).split())[:64]
    if not value or any(ord(char) < 32 for char in value):
        raise QuotaError("invalid-label")
    return value


class Accounts:
    def __init__(self, root: Path | None = None):
        self.root = private_directory(root or Path(os.environ.get("XDG_STATE_HOME", str(Path.home() / ".local/state")))
                                      / "illogical-impulse/ai-quotas")
        self.path = self.root / "accounts.json"

    @contextmanager
    def locked(self) -> Iterator[dict]:
        with file_lock(self.root / "accounts.lock"):
            data = read_json(self.path, {"version": 1, "accounts": [], "selected": {}, "generations": {}})
            self.validate(data)
            yield data

    @staticmethod
    def validate(data: dict) -> None:
        if (data.get("version") != 1 or not isinstance(data.get("accounts"), list)
                or len(data["accounts"]) > 50 or not isinstance(data.get("selected"), dict)
                or not isinstance(data.get("generations"), dict)):
            raise QuotaError("invalid-storage")
        ids = set()
        for account in data["accounts"]:
            if not isinstance(account, dict):
                raise QuotaError("invalid-storage")
            account_id = opaque_id(account.get("id"))
            credential = opaque_id(account.get("credential"))
            provider = account.get("provider")
            if (account_id in ids or provider not in PROVIDERS
                    or account.get("source") not in PROVIDERS[provider][1]
                    or clean_label(account.get("alias", "")) != account["alias"] or not credential):
                raise QuotaError("invalid-storage")
            ids.add(account_id)
        for provider, selected in data["selected"].items():
            if provider not in PROVIDERS or (selected is not None and not any(
                    a["id"] == selected and a["provider"] == provider for a in data["accounts"])):
                raise QuotaError("invalid-storage")
        if any(p not in PROVIDERS or type(g) is not int or g < 0 for p, g in data["generations"].items()):
            raise QuotaError("invalid-storage")

    def read(self) -> dict:
        with self.locked() as data:
            return data

    def mutate(self, action: str, account_id: str, *, alias: str = "") -> None:
        with self.locked() as data:
            account = next((a for a in data["accounts"] if a["id"] == account_id), None)
            if not account:
                raise QuotaError("invalid-account")
            provider = account["provider"]
            if action == "select":
                data["selected"][provider] = account_id
            elif action == "disable":
                data["selected"][provider] = None
            elif action == "rename":
                account["alias"] = clean_label(alias)
            elif action == "remove":
                data["accounts"].remove(account)
                if data["selected"].get(provider) == account_id:
                    data["selected"][provider] = None
            elif action != "invalidate":
                raise QuotaError("invalid-action")
            data["generations"][provider] = data["generations"].get(provider, 0) + 1
            write_json(self.path, data)

    def add(self, provider: str, source: str, alias: str, credential: str) -> str:
        if provider not in PROVIDERS or source not in PROVIDERS[provider][1]:
            raise QuotaError("unsupported-source")
        alias, credential = clean_label(alias), opaque_id(credential)
        with self.locked() as data:
            if len(data["accounts"]) >= 50:
                raise QuotaError("account-limit")
            # Native client modes follow ONE active login, not fictitious pinned profiles.
            if managed_source(source) and any(
                    a["source"] == source and a["provider"] == provider for a in data["accounts"]):
                raise QuotaError("active-session-exists")
            account_id = uuid.uuid4().hex
            data["accounts"].append({"id": account_id, "provider": provider, "source": source,
                                     "alias": alias, "credential": credential})
            data["selected"][provider] = account_id
            data["generations"][provider] = data["generations"].get(provider, 0) + 1
            write_json(self.path, data)
        return account_id

    def replace_credential(self, account_id: str, old: str, new: str) -> None:
        with self.locked() as data:
            account = next((a for a in data["accounts"] if a["id"] == account_id), None)
            if not account or account["credential"] != old:
                raise QuotaError("account-changed")
            account["credential"] = opaque_id(new)
            provider = account["provider"]
            data["generations"][provider] = data["generations"].get(provider, 0) + 1
            write_json(self.path, data)


class Vault:
    """SecretStorage's GetSecret never invokes Unlock; setup is explicit too."""

    def __init__(self):
        try:
            secretstorage = importlib.import_module("secretstorage")
        except ImportError as error:
            raise QuotaError("secret-service-dependency") from error
        self.api = secretstorage

    @contextmanager
    def connection(self):
        try:
            connection = self.api.dbus_init()
            try:
                yield connection
            finally:
                connection.close()
        except QuotaError:
            raise
        except Exception as error:
            # Deliberate trust boundary: never stringify DBus errors/secret payloads.
            raise QuotaError("keyring-unavailable") from error

    @staticmethod
    def attributes(provider: str, credential: str) -> dict:
        if provider not in PROVIDERS:
            raise QuotaError("unsupported-source")
        return {"application": APPLICATION, "provider": provider, "credential": opaque_id(credential)}

    def get(self, provider: str, credential: str) -> str:
        attributes = self.attributes(provider, credential)
        with self.connection() as connection:
            items = list(self.api.search_items(connection, attributes))
            if len(items) != 1:
                raise QuotaError("credential-missing")
            if items[0].is_locked():
                raise QuotaError("locked")
            value = items[0].get_secret()
            if len(value) > 16384:
                raise QuotaError("invalid-credential")
            return value.decode("utf-8")

    def store(self, provider: str, credential: str, value: str) -> None:
        attributes = self.attributes(provider, credential)
        with self.connection() as connection:
            collection = self.api.get_default_collection(connection)
            if collection.is_locked():
                raise QuotaError("locked")
            collection.create_item(f"AI quota · {provider}", attributes, value.encode(), replace=True)

    def delete(self, provider: str, credential: str) -> None:
        attributes = self.attributes(provider, credential)
        with self.connection() as connection:
            for item in self.api.search_items(connection, attributes):
                if item.is_locked():
                    raise QuotaError("locked")
                item.delete()
