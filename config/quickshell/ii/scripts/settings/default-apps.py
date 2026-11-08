#!/usr/bin/env python3
"""Query and set default applications per role (browser, image viewer, ...).

Implements the lookup rules of the freedesktop.org "Association between MIME
types and applications" and "Desktop Entry" specifications directly instead of
calling `xdg-mime`, so results are deterministic under a temporary XDG
environment and one call answers every role without spawning a process per
MIME type.

Exit codes: 0 ok, 1 I/O error, 2 usage or validation error. Diagnostics go to
stderr; stdout carries only the requested output.
"""
from __future__ import annotations

import argparse
import json
import os
import shutil
import sys
import tempfile
from pathlib import Path

# Each role maps to the MIME types a user expects that role to own. The first
# type is the primary one whose default represents the role. Types are the
# canonical shared-mime-info names because mimeapps.list lookups match the
# exact string and this tool does not resolve aliases or subclasses.
ROLES: dict[str, tuple[str, ...]] = {
    # xdg-open on a URL asks for the scheme handler, so http is primary;
    # text/html covers opening local .html files.
    "browser": ("x-scheme-handler/http", "x-scheme-handler/https", "text/html"),
    "fileManager": ("inode/directory",),
    "mail": ("x-scheme-handler/mailto",),
    # Raster and vector formats that common viewers (imv, Loupe, Eye of GNOME,
    # gwenview) declare; exotic camera formats are left to explicit choices.
    "image": ("image/png", "image/jpeg", "image/gif", "image/webp", "image/bmp",
              "image/svg+xml", "image/tiff"),
    # Containers produced by browsers, phones and screen recorders.
    "video": ("video/mp4", "video/x-matroska", "video/webm", "video/quicktime",
              "video/x-msvideo", "video/mpeg", "video/ogg"),
    "audio": ("audio/mpeg", "audio/flac", "audio/ogg", "audio/x-vorbis+ogg",
              "audio/x-opus+ogg", "audio/x-wav", "audio/mp4", "audio/aac"),
    # Only text/plain: source-code types are subclasses that editors usually
    # declare individually, and forcing them would override IDE choices.
    "text": ("text/plain",),
    "pdf": ("application/pdf",),
}

DEFAULT_GROUP = "Default Applications"
ADDED_GROUP = "Added Associations"
REMOVED_GROUP = "Removed Associations"

_warned: set[str] = set()


def warn(message: str) -> None:
    if message not in _warned:
        _warned.add(message)
        print(f"default-apps: warning: {message}", file=sys.stderr)


class UsageError(Exception):
    pass


# ---------------------------------------------------------------- environment

def _home() -> Path:
    return Path(os.environ.get("HOME") or os.path.expanduser("~"))


def _env_dir(name: str, fallback: str) -> Path:
    value = os.environ.get(name, "")
    path = Path(value) if value and os.path.isabs(value) else _home() / fallback
    return path


def _env_dirs(name: str, fallback: str) -> list[Path]:
    # The spec ignores relative entries; an empty variable means the default.
    entries = [Path(p) for p in os.environ.get(name, "").split(":") if os.path.isabs(p)]
    return entries or [Path(p) for p in fallback.split(":")]


def config_home() -> Path:
    return _env_dir("XDG_CONFIG_HOME", ".config")


def data_dirs() -> list[Path]:
    return [_env_dir("XDG_DATA_HOME", ".local/share")] + _env_dirs(
        "XDG_DATA_DIRS", "/usr/local/share:/usr/share")


def current_desktops() -> list[str]:
    # The settings app only runs under Hyprland; assume it when the session
    # variable is missing (for example when launched from a bare terminal).
    names = [d for d in os.environ.get("XDG_CURRENT_DESKTOP", "").split(":") if d]
    return names or ["Hyprland"]


def locale_candidates() -> list[str]:
    # Desktop Entry spec, "Localized values for keys": LC_MESSAGES semantics.
    raw = ""
    for name in ("LC_ALL", "LC_MESSAGES", "LANG"):
        raw = os.environ.get(name, "")
        if raw:
            break
    if not raw or raw in ("C", "POSIX") or raw.startswith(("C.", "POSIX.")):
        return []
    lang, _, modifier = raw.partition("@")
    lang = lang.split(".", 1)[0]
    language, _, country = lang.partition("_")
    out = []
    if country and modifier:
        out.append(f"{language}_{country}@{modifier}")
    if country:
        out.append(f"{language}_{country}")
    if modifier:
        out.append(f"{language}@{modifier}")
    out.append(language)
    return out


# ------------------------------------------------------------- file parsing

def read_text(path: Path) -> str | None:
    try:
        return path.read_text(encoding="utf-8")
    except FileNotFoundError:
        return None
    except UnicodeDecodeError:
        warn(f"skipping {path}: not valid UTF-8")
    except OSError as error:
        warn(f"skipping {path}: {error.strerror or error}")
    return None


def parse_ini(text: str, path: Path) -> dict[str, dict[str, str]]:
    """Parse a desktop-entry-style file. First occurrence of a key wins."""
    groups: dict[str, dict[str, str]] = {}
    current: dict[str, str] | None = None
    for number, line in enumerate(text.splitlines(), 1):
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        if stripped.startswith("[") and stripped.endswith("]"):
            current = groups.setdefault(stripped[1:-1], {})
            continue
        key, sep, value = stripped.partition("=")
        if not sep or current is None or not key.strip():
            warn(f"{path}:{number}: ignoring malformed line")
            continue
        current.setdefault(key.strip(), value.strip())
    return groups


def unescape(value: str) -> str:
    out, i = [], 0
    while i < len(value):
        char = value[i]
        if char == "\\" and i + 1 < len(value):
            nxt = value[i + 1]
            out.append({"s": " ", "n": "\n", "t": "\t", "r": "\r", "\\": "\\"}.get(nxt, "\\" + nxt))
            i += 2
            continue
        out.append(char)
        i += 1
    return "".join(out)


def split_list(value: str | None) -> list[str]:
    return [item.strip() for item in (value or "").split(";") if item.strip()]


def is_true(value: str | None) -> bool:
    return (value or "").strip().lower() == "true"


# ------------------------------------------------------------ desktop files

class App:
    __slots__ = ("id", "path", "name", "icon", "mime_types", "hidden", "visible")

    def __init__(self, app_id, path, name, icon, mime_types, hidden, visible):
        self.id = app_id
        self.path = path
        self.name = name
        self.icon = icon
        self.mime_types = mime_types
        self.hidden = hidden
        self.visible = visible


def _try_exec_ok(value: str) -> bool:
    if os.path.isabs(value):
        return os.access(value, os.X_OK)
    return shutil.which(value) is not None


def load_app(app_id: str, path: Path, desktops: list[str], locales: list[str]) -> App | None:
    text = read_text(path)
    if text is None:
        return None
    entry = parse_ini(text, path).get("Desktop Entry")
    if entry is None:
        warn(f"skipping {path}: no [Desktop Entry] group")
        return None
    hidden = is_true(entry.get("Hidden"))
    if not hidden and entry.get("Type") != "Application":
        return None
    name = None
    for loc in locales:
        if f"Name[{loc}]" in entry:
            name = entry[f"Name[{loc}]"]
            break
    name = unescape(name if name is not None else entry.get("Name", ""))
    if not hidden and not name:
        warn(f"skipping {path}: missing Name")
        return None
    lowered = {d.lower() for d in desktops}
    only = {d.lower() for d in split_list(entry.get("OnlyShowIn"))}
    never = {d.lower() for d in split_list(entry.get("NotShowIn"))}
    visible = not hidden and not is_true(entry.get("NoDisplay"))
    if visible and only and not (only & lowered):
        visible = False
    if visible and never & lowered:
        visible = False
    try_exec = entry.get("TryExec")
    if visible and try_exec and not _try_exec_ok(unescape(try_exec)):
        visible = False
    return App(app_id, path, name, unescape(entry.get("Icon", "")),
               split_list(entry.get("MimeType")), hidden, visible)


def scan_apps(desktops: list[str], locales: list[str]) -> dict[str, App]:
    """Map desktop id to its highest-precedence entry (Hidden ones included)."""
    apps: dict[str, App] = {}
    for base in data_dirs():
        root = base / "applications"
        if not root.is_dir():
            continue
        for dirpath, dirnames, filenames in os.walk(root, onerror=lambda e: warn(f"cannot read {e.filename}: {e.strerror}")):
            dirnames.sort()
            for filename in sorted(filenames):
                if not filename.endswith(".desktop"):
                    continue
                path = Path(dirpath) / filename
                app_id = str(path.relative_to(root)).replace(os.sep, "-")
                if app_id in apps:
                    continue
                app = load_app(app_id, path, desktops, locales)
                if app is not None:
                    apps[app_id] = app
    return apps


# ---------------------------------------------------------- mimeapps lookup

def mimeapps_files(desktops: list[str]) -> list[Path]:
    """mimeapps.list locations in the spec's precedence order."""
    names = [f"{d.lower()}-mimeapps.list" for d in desktops] + ["mimeapps.list"]
    dirs = [config_home()] + _env_dirs("XDG_CONFIG_DIRS", "/etc/xdg")
    dirs += [base / "applications" for base in data_dirs()]
    return [directory / name for directory in dirs for name in names]


def load_mimeapps(desktops: list[str]) -> list[dict[str, dict[str, str]]]:
    loaded = []
    for path in mimeapps_files(desktops):
        text = read_text(path)
        if text is not None:
            loaded.append(parse_ini(text, path))
    return loaded


def resolve_default(mime: str, files, apps: dict[str, App]) -> tuple[str | None, bool]:
    """Return (desktop id, explicit) where explicit means [Default Applications]."""
    def installed(app_id: str) -> bool:
        app = apps.get(app_id)
        return app is not None and not app.hidden

    for groups in files:
        for app_id in split_list(groups.get(DEFAULT_GROUP, {}).get(mime)):
            if installed(app_id):
                return app_id, True
    # No valid default: fall back to the most preferred association.
    removed: set[str] = set()
    for groups in files:
        for app_id in split_list(groups.get(ADDED_GROUP, {}).get(mime)):
            if app_id not in removed and installed(app_id):
                return app_id, False
        removed.update(split_list(groups.get(REMOVED_GROUP, {}).get(mime)))
    for app in apps.values():
        if not app.hidden and mime in app.mime_types and app.id not in removed:
            return app.id, False
    return None, False


def role_state(role: str, apps: dict[str, App], files) -> dict:
    types = ROLES[role]
    defaults, explicit = {}, {}
    for mime in types:
        defaults[mime], explicit[mime] = resolve_default(mime, files, apps)
    current = defaults[types[0]]
    current_app = apps.get(current) if current else None
    # A candidate must open the primary type: the role shows that type's
    # default, so picking an app without it would appear to change nothing.
    candidates = [
        {
            "id": app.id,
            "name": app.name,
            "icon": app.icon,
            "handlesAll": all(t in app.mime_types for t in types),
        }
        for app in sorted(apps.values(), key=lambda a: (a.name.casefold(), a.id))
        if app.visible and types[0] in app.mime_types
    ]
    return {
        "role": role,
        "types": list(types),
        "primaryType": types[0],
        "current": current,
        "currentName": current_app.name if current_app else None,
        "explicit": explicit[types[0]],
        "mixed": len(set(defaults.values())) > 1,
        "defaults": defaults,
        "candidates": candidates,
    }


def full_state(roles=None) -> dict:
    desktops = current_desktops()
    apps = scan_apps(desktops, locale_candidates())
    files = load_mimeapps(desktops)
    return {
        "desktops": desktops,
        "roles": {role: role_state(role, apps, files) for role in (roles or ROLES)},
    }


# ---------------------------------------------------------- mimeapps writer

def _is_group(line: str) -> str | None:
    stripped = line.strip()
    if stripped.startswith("[") and stripped.endswith("]"):
        return stripped[1:-1]
    return None


def _key(line: str) -> str | None:
    stripped = line.strip()
    if not stripped or stripped.startswith("#") or "=" not in stripped:
        return None
    return stripped.split("=", 1)[0].strip()


def update_defaults(text: str, values: dict[str, str], create: bool) -> str:
    """Rewrite [Default Applications] keys in `values`, keeping everything else.

    With create=False only keys already present are rewritten; this is used for
    desktop-specific files that would otherwise shadow mimeapps.list.
    """
    lines = text.splitlines(keepends=True)
    if lines and not lines[-1].endswith("\n"):
        lines[-1] += "\n"
    out: list[str] = []
    pending = dict(values)
    seen_group = False
    in_group = False
    insert_at = None
    for line in lines:
        group = _is_group(line)
        if group is not None:
            if in_group and insert_at is None:
                insert_at = len(out)
            in_group = group == DEFAULT_GROUP
            seen_group = seen_group or in_group
            out.append(line)
            continue
        key = _key(line) if in_group else None
        if key in values:
            if key in pending:
                out.append(f"{key}={pending.pop(key)};\n")
            # Later duplicates would be ignored by readers; drop them so the
            # file states one unambiguous default.
            continue
        out.append(line)
    if in_group and insert_at is None:
        insert_at = len(out)
    if create and pending:
        new = [f"{k}={v};\n" for k, v in pending.items()]
        if seen_group:
            # Keep insertions above trailing blank lines of the first group.
            while insert_at > 0 and not out[insert_at - 1].strip():
                insert_at -= 1
            out[insert_at:insert_at] = new
        else:
            if out and out[-1].strip():
                out.append("\n")
            out.append(f"[{DEFAULT_GROUP}]\n")
            out.extend(new)
    return "".join(out)


def atomic_write(path: Path, text: str) -> None:
    target = Path(os.path.realpath(path))
    target.parent.mkdir(parents=True, exist_ok=True)
    try:
        mode = target.stat().st_mode & 0o7777
    except FileNotFoundError:
        umask = os.umask(0)
        os.umask(umask)
        mode = 0o666 & ~umask
    fd, tmp = tempfile.mkstemp(prefix=".mimeapps.", dir=target.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8", errors="surrogateescape", newline="") as handle:
            handle.write(text)
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(tmp, mode)
        os.replace(tmp, target)
    except BaseException:
        try:
            os.unlink(tmp)
        except FileNotFoundError:
            pass
        raise


def read_for_update(path: Path) -> str | None:
    # surrogateescape round-trips undecodable bytes so foreign content survives.
    try:
        return path.read_text(encoding="utf-8", errors="surrogateescape")
    except FileNotFoundError:
        return None


def set_default(role: str, app_id: str) -> dict:
    if role not in ROLES:
        raise UsageError(f"unknown role {role!r}; expected one of: {', '.join(ROLES)}")
    desktops = current_desktops()
    apps = scan_apps(desktops, locale_candidates())
    state = role_state(role, apps, load_mimeapps(desktops))
    if app_id not in {c["id"] for c in state["candidates"]}:
        raise UsageError(f"{app_id!r} is not a candidate for role {role!r}")
    # Only the types the app declares: claiming the others would make
    # xdg-open hand it files it cannot open. Those keep their current default.
    declared = set(apps[app_id].mime_types)
    values = {mime: app_id for mime in ROLES[role] if mime in declared}
    written = []
    home = config_home()
    for desktop in current_desktops():
        path = home / f"{desktop.lower()}-mimeapps.list"
        text = read_for_update(path)
        if text is None:
            continue
        updated = update_defaults(text, values, create=False)
        if updated != text:
            atomic_write(path, updated)
            written.append(str(path))
    path = home / "mimeapps.list"
    text = read_for_update(path) or ""
    updated = update_defaults(text, values, create=True)
    if updated != text:
        atomic_write(path, updated)
        written.append(str(path))
    return {"written": written, "role": full_state([role])["roles"][role]}


# ---------------------------------------------------------------------- CLI

def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="default-apps.py", description=__doc__.splitlines()[0])
    sub = parser.add_subparsers(dest="command", required=True)
    list_parser = sub.add_parser("list", help="show defaults and candidates for every role")
    list_parser.add_argument("--json", action="store_true", help="machine-readable output")
    set_parser = sub.add_parser("set", help="set the default application of a role")
    set_parser.add_argument("role", help=", ".join(ROLES))
    set_parser.add_argument("desktop_id", help="desktop file id, e.g. firefox.desktop")
    args = parser.parse_args(argv)
    try:
        if args.command == "list":
            state = full_state()
            if args.json:
                print(json.dumps(state, ensure_ascii=False))
            else:
                for role, info in state["roles"].items():
                    flag = " (mixed)" if info["mixed"] else ""
                    print(f"{role}: {info['current'] or '-'}{flag}")
        else:
            print(json.dumps(set_default(args.role, args.desktop_id), ensure_ascii=False))
    except UsageError as error:
        print(f"default-apps: error: {error}", file=sys.stderr)
        return 2
    except OSError as error:
        print(f"default-apps: error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
