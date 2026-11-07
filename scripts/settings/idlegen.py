#!/usr/bin/env python3
"""Render hypridle listeners for the settings app.

Usage:
    idlegen.py [--lock S] [--dpms S] [--suspend S] [--output PATH] [--force] [--print]

Timeouts are seconds; 0 means never (no listener). Non-zero values must be in
30..86400 and ordered lock <= dpms <= suspend. The file is written atomically to
~/.config/hypr/custom/shell-idle.conf (sourced by hypridle.conf) unless --print.

Exit codes: 0 written/printed, 1 I/O error, 2 invalid arguments,
3 target exists without the managed marker (use --force).
"""
from __future__ import annotations

import argparse
import os
import sys
import tempfile
from pathlib import Path

MARKER = '# managed by the settings app (scripts/settings/idlegen.py); manual edits are overwritten'
DEFAULT_OUTPUT = Path.home() / '.config/hypr/custom/shell-idle.conf'
MIN_TIMEOUT, MAX_TIMEOUT = 30, 86400

# Commands mirror the commented examples in config/hypr/hypridle.conf.
LOCK_CMD = 'loginctl lock-session'
DPMS_OFF_CMD = """hyprctl dispatch 'hl.dsp.dpms({ action = "disable" })'"""
DPMS_ON_CMD = """hyprctl dispatch 'hl.dsp.dpms({ action = "enable" })'"""
# Inlined instead of $suspend_cmd so the file does not depend on a variable
# defined by whichever file sources it.
SUSPEND_CMD = 'systemctl suspend || loginctl suspend'

EXIT_IO, EXIT_INVALID, EXIT_UNMANAGED = 1, 2, 3


class IdleError(ValueError):
    pass


def validate(lock: int, dpms: int, suspend: int) -> None:
    named = (('lock', lock), ('dpms', dpms), ('suspend', suspend))
    for name, value in named:
        if isinstance(value, bool) or not isinstance(value, int):
            raise IdleError(f'{name} timeout must be an integer, got {value!r}')
        if value != 0 and not MIN_TIMEOUT <= value <= MAX_TIMEOUT:
            raise IdleError(f'{name} timeout must be 0 (never) or {MIN_TIMEOUT}..{MAX_TIMEOUT} seconds, got {value}')
    active = [(name, value) for name, value in named if value]
    for (first, a), (second, b) in zip(active, active[1:]):
        if a > b:
            raise IdleError(f'{first} timeout ({a}s) must not exceed {second} timeout ({b}s)')


def render(lock: int, dpms: int, suspend: int) -> str:
    validate(lock, dpms, suspend)
    lines = [MARKER, '# Sourced by ~/.config/hypr/hypridle.conf. A missing listener means never.']
    if lock:
        lines += ['', 'listener {', f'    timeout = {lock}', f'    on-timeout = {LOCK_CMD}', '}']
    if dpms:
        lines += ['', 'listener {', f'    timeout = {dpms}', f'    on-timeout = {DPMS_OFF_CMD}',
                  f'    on-resume = {DPMS_ON_CMD}', '}']
    if suspend:
        lines += ['', 'listener {', f'    timeout = {suspend}', f'    on-timeout = {SUSPEND_CMD}', '}']
    return '\n'.join(lines) + '\n'


def is_managed(path: Path) -> bool:
    with path.open('r', encoding='utf-8', errors='replace') as handle:
        return handle.readline().rstrip('\n') == MARKER


def atomic_write(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temp = tempfile.mkstemp(prefix=f'.{path.name}.', suffix='.tmp', dir=path.parent)
    try:
        with os.fdopen(fd, 'w', encoding='utf-8') as handle:
            handle.write(content)
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(temp, 0o644)
        os.replace(temp, path)
    except BaseException:
        Path(temp).unlink(missing_ok=True)
        raise


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description='Render hypridle listeners for the settings app.')
    parser.add_argument('--lock', type=int, default=0, help='seconds before locking; 0 = never')
    parser.add_argument('--dpms', type=int, default=0, help='seconds before turning displays off; 0 = never')
    parser.add_argument('--suspend', type=int, default=0, help='seconds before suspending; 0 = never')
    parser.add_argument('--output', type=Path, default=DEFAULT_OUTPUT, help='target file')
    parser.add_argument('--force', action='store_true', help='overwrite a target without the managed marker')
    parser.add_argument('--print', action='store_true', help='write to stdout instead of the target')
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(sys.argv[1:] if argv is None else argv)
    try:
        content = render(args.lock, args.dpms, args.suspend)
    except IdleError as error:
        print(f'idlegen: {error}', file=sys.stderr)
        return EXIT_INVALID
    if args.print:
        sys.stdout.write(content)
        return 0
    target: Path = args.output
    try:
        if target.is_symlink() or (target.exists() and not target.is_file()):
            print(f'idlegen: refusing non-regular target {target}', file=sys.stderr)
            return EXIT_UNMANAGED
        if target.exists() and not args.force and not is_managed(target):
            print(f'idlegen: {target} is not managed by the settings app; use --force to overwrite',
                  file=sys.stderr)
            return EXIT_UNMANAGED
        atomic_write(target, content)
    except OSError as error:
        print(f'idlegen: cannot write {target}: {error}', file=sys.stderr)
        return EXIT_IO
    return 0


if __name__ == '__main__':
    sys.exit(main())
