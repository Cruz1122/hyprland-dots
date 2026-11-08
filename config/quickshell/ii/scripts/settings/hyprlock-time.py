#!/usr/bin/env python3
"""Switch the hyprlock clock between 24-hour ($TIME) and 12-hour ($TIME12).

Replaces the old `bash -c "sed -i ..."` call of the settings app: the mode is
validated, the file is rewritten atomically (keeping its mode and following a
symlink instead of replacing it), and nothing goes through a shell.

Usage: hyprlock-time.py 24h|12h [--file PATH]
Exit codes: 0 ok (also when the file does not exist), 1 I/O error, 2 usage.
"""
from __future__ import annotations

import argparse
import os
import re
import sys
import tempfile
from pathlib import Path

# `\b` keeps $TIME from matching inside $TIME12 and vice versa.
PATTERNS = {
    "24h": (re.compile(r"\$TIME12\b"), "$TIME"),
    "12h": (re.compile(r"\$TIME\b"), "$TIME12"),
}


def default_file() -> Path:
    base = os.environ.get("XDG_CONFIG_HOME", "")
    root = Path(base) if os.path.isabs(base) else Path.home() / ".config"
    return root / "hypr" / "hyprlock.conf"


def convert(text: str, mode: str) -> str:
    pattern, replacement = PATTERNS[mode]
    return pattern.sub(lambda _: replacement, text)


def atomic_write(path: Path, text: str) -> None:
    target = Path(os.path.realpath(path))
    mode = target.stat().st_mode & 0o7777
    fd, tmp = tempfile.mkstemp(prefix=".hyprlock.", dir=target.parent)
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


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="hyprlock-time.py", description=__doc__.splitlines()[0])
    parser.add_argument("mode", choices=sorted(PATTERNS))
    parser.add_argument("--file", type=Path, default=None, help="hyprlock.conf (default: $XDG_CONFIG_HOME/hypr/hyprlock.conf)")
    args = parser.parse_args(argv)
    path = args.file or default_file()
    try:
        text = path.read_text(encoding="utf-8", errors="surrogateescape")
    except FileNotFoundError:
        print(f"hyprlock-time: {path} does not exist; nothing to change", file=sys.stderr)
        return 0
    except OSError as error:
        print(f"hyprlock-time: error: {error}", file=sys.stderr)
        return 1
    updated = convert(text, args.mode)
    if updated == text:
        return 0
    try:
        atomic_write(path, updated)
    except OSError as error:
        print(f"hyprlock-time: error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
