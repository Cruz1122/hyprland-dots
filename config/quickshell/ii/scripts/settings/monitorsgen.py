#!/usr/bin/env python3
"""Render Hyprland monitor rules (Lua) for the settings app.

Usage:
    monitorsgen.py [--output PATH] [--force] [--print | --lua-expr [--name OUTPUT]] [--spec-json TEXT] < spec.json

The spec is read from --spec-json when given (the settings app passes it as an
argv item), otherwise from stdin. It is a JSON object {"monitors": [MONITOR, ...]} where MONITOR is:
    name       string, required (e.g. "eDP-1", "desc:...")
    enabled    bool, default true
    mode       "preferred" (default) or "WxH@Hz" (optional "Hz" suffix)
    position   "auto" (default) or {"x": int, "y": int}
    scale      number 0.25..10, default 1
    transform  int 0..7, default 0
    mirror     output name or null (default)
    vrr        int 0..2 (bool accepted), default 0
    bitdepth   8, 10 or null (default)
Unknown keys, duplicate names, self-mirroring and an all-disabled layout are
rejected. Rules are emitted enabled-first (stable), so outputs are turned on
before others are turned off.

Default: atomically write ~/.config/hypr/monitors.lua. A target without the
managed marker is refused unless --force, which first backs it up next to it
as <name>.bak-YYYYmmdd-HHMMSS. --print writes the file content to stdout.
--lua-expr writes the same hl.monitor({...}) calls joined by "; " on one line
(for a single `hyprctl eval` argument); --name limits it to one output.

Exit codes: 0 ok, 1 I/O error, 2 invalid input, 3 target exists without the
managed marker.
"""
from __future__ import annotations

import argparse
import json
import math
import os
import re
import shutil
import sys
import tempfile
import time
from pathlib import Path

MARKER = '-- managed by the settings app (scripts/settings/monitorsgen.py); manual edits are overwritten'
DEFAULT_OUTPUT = Path.home() / '.config/hypr/monitors.lua'
EXIT_IO, EXIT_INVALID, EXIT_UNMANAGED = 1, 2, 3

FIELDS = ('name', 'enabled', 'mode', 'position', 'scale', 'transform', 'mirror', 'vrr', 'bitdepth')
MODE_RE = re.compile(r'(\d{1,5})x(\d{1,5})@(\d{1,4}(?:\.\d{1,3})?)(Hz)?')
MAX_NAME = 128
MAX_COORD = 65536


class SpecError(ValueError):
    pass


def _is_int(value: object) -> bool:
    return isinstance(value, int) and not isinstance(value, bool)


def _text(value: object, where: str) -> str:
    if not isinstance(value, str) or not value:
        raise SpecError(f'{where} must be a non-empty string')
    if len(value) > MAX_NAME:
        raise SpecError(f'{where} is longer than {MAX_NAME} characters')
    if not value.isprintable():
        raise SpecError(f'{where} contains control characters')
    return value


def quote_lua(value: str) -> str:
    return '"' + value.replace('\\', '\\\\').replace('"', '\\"') + '"'


def format_number(value: float) -> str:
    return str(int(value)) if float(value).is_integer() else repr(float(value))


def normalize(raw: object, index: int) -> dict:
    where = f'monitors[{index}]'
    if not isinstance(raw, dict):
        raise SpecError(f'{where} must be an object')
    unknown = sorted(set(raw) - set(FIELDS))
    if unknown:
        raise SpecError(f'{where} has unknown fields: {", ".join(unknown)}')
    if 'name' not in raw:
        raise SpecError(f'{where}.name is required')
    name = _text(raw['name'], f'{where}.name')

    enabled = raw.get('enabled', True)
    if not isinstance(enabled, bool):
        raise SpecError(f'{where}.enabled must be a boolean')

    mode = raw.get('mode', 'preferred')
    if mode != 'preferred':
        match = MODE_RE.fullmatch(mode) if isinstance(mode, str) else None
        if not match:
            raise SpecError(f'{where}.mode must be "preferred" or WxH@Hz, got {mode!r}')
        width, height, rate = int(match[1]), int(match[2]), float(match[3])
        if not (1 <= width <= 16384 and 1 <= height <= 16384 and 1 <= rate <= 1000):
            raise SpecError(f'{where}.mode is out of range: {mode}')

    position = raw.get('position', 'auto')
    if position == 'auto':
        position_text = 'auto'
    elif isinstance(position, dict) and set(position) == {'x', 'y'}:
        x, y = position['x'], position['y']
        if not (_is_int(x) and _is_int(y) and abs(x) <= MAX_COORD and abs(y) <= MAX_COORD):
            raise SpecError(f'{where}.position x/y must be integers within ±{MAX_COORD}')
        position_text = f'{x}x{y}'
    else:
        raise SpecError(f'{where}.position must be "auto" or {{"x": int, "y": int}}')

    scale = raw.get('scale', 1)
    if isinstance(scale, bool) or not isinstance(scale, (int, float)) or not math.isfinite(scale) \
            or not 0.25 <= scale <= 10:
        raise SpecError(f'{where}.scale must be a number in 0.25..10')

    transform = raw.get('transform', 0)
    if not _is_int(transform) or not 0 <= transform <= 7:
        raise SpecError(f'{where}.transform must be an integer in 0..7')

    mirror = raw.get('mirror')
    if mirror is not None:
        mirror = _text(mirror, f'{where}.mirror')
        if mirror == name:
            raise SpecError(f'{where}.mirror cannot be the monitor itself')

    vrr = raw.get('vrr', 0)
    if isinstance(vrr, bool):
        vrr = int(vrr)
    if not _is_int(vrr) or not 0 <= vrr <= 2:
        raise SpecError(f'{where}.vrr must be 0, 1, 2 or a boolean')

    bitdepth = raw.get('bitdepth')
    if bitdepth is not None and (not _is_int(bitdepth) or bitdepth not in (8, 10)):
        raise SpecError(f'{where}.bitdepth must be 8, 10 or null')

    return {'name': name, 'enabled': enabled, 'mode': mode, 'position': position_text,
            'scale': scale, 'transform': transform, 'mirror': mirror, 'vrr': vrr, 'bitdepth': bitdepth}


def parse_spec(spec: object) -> list[dict]:
    if not isinstance(spec, dict) or set(spec) != {'monitors'} or not isinstance(spec['monitors'], list):
        raise SpecError('spec must be an object with only a "monitors" list')
    monitors = [normalize(raw, index) for index, raw in enumerate(spec['monitors'])]
    if not monitors:
        raise SpecError('spec must contain at least one monitor')
    names = [monitor['name'] for monitor in monitors]
    duplicates = sorted({name for name in names if names.count(name) > 1})
    if duplicates:
        raise SpecError(f'duplicate monitor names: {", ".join(duplicates)}')
    if not any(monitor['enabled'] for monitor in monitors):
        raise SpecError('at least one monitor must stay enabled')
    # Enabling first avoids a moment with no active output while Hyprland
    # applies the rules in order (same ordering as DisplayControl.qml).
    return sorted(monitors, key=lambda monitor: not monitor['enabled'])


def lua_table(monitor: dict) -> str:
    parts = [
        f'output = {quote_lua(monitor["name"])}',
        f'mode = {quote_lua(monitor["mode"])}',
        f'position = {quote_lua(monitor["position"])}',
        f'scale = {format_number(monitor["scale"])}',
        f'transform = {monitor["transform"]}',
        f'disabled = {"false" if monitor["enabled"] else "true"}',
        f'vrr = {monitor["vrr"]}',
    ]
    if monitor['mirror'] is not None:
        parts.append(f'mirror = {quote_lua(monitor["mirror"])}')
    if monitor['bitdepth'] is not None:
        parts.append(f'bitdepth = {monitor["bitdepth"]}')
    return '{ ' + ', '.join(parts) + ' }'


def lua_call(monitor: dict) -> str:
    return f'hl.monitor({lua_table(monitor)})'


def render_file(monitors: list[dict]) -> str:
    lines = [MARKER, '-- Loaded by ~/.config/hypr/hyprland.lua when present.', '']
    lines += [lua_call(monitor) for monitor in monitors]
    return '\n'.join(lines) + '\n'


def render_expr(monitors: list[dict], name: str | None = None) -> str:
    selected = [monitor for monitor in monitors if name is None or monitor['name'] == name]
    if not selected:
        raise SpecError(f'monitor {name!r} is not in the spec')
    return '; '.join(lua_call(monitor) for monitor in selected)


def is_managed(path: Path) -> bool:
    with path.open('r', encoding='utf-8', errors='replace') as handle:
        return handle.readline().rstrip('\n') == MARKER


def backup(path: Path) -> Path:
    stamp = time.strftime('%Y%m%d-%H%M%S')
    candidate = path.with_name(f'{path.name}.bak-{stamp}')
    counter = 1
    while candidate.exists():
        candidate = path.with_name(f'{path.name}.bak-{stamp}-{counter}')
        counter += 1
    shutil.copy2(path, candidate)
    return candidate


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
    parser = argparse.ArgumentParser(description='Render Hyprland monitor rules from a JSON spec on stdin.')
    parser.add_argument('--output', type=Path, default=DEFAULT_OUTPUT, help='target monitors.lua')
    parser.add_argument('--force', action='store_true', help='back up and overwrite an unmanaged target')
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument('--print', action='store_true', help='write the file content to stdout')
    mode.add_argument('--lua-expr', action='store_true', help='write one-line hl.monitor() calls to stdout')
    parser.add_argument('--name', help='with --lua-expr, only this output')
    parser.add_argument('--spec-json', help='JSON spec as text instead of stdin')
    args = parser.parse_args(argv)
    if args.name is not None and not args.lua_expr:
        parser.error('--name requires --lua-expr')
    return args


def main(argv: list[str] | None = None) -> int:
    args = parse_args(sys.argv[1:] if argv is None else argv)
    try:
        raw = json.loads(args.spec_json) if args.spec_json is not None else json.load(sys.stdin)
        monitors = parse_spec(raw)
        if args.lua_expr:
            sys.stdout.write(render_expr(monitors, args.name) + '\n')
            return 0
        content = render_file(monitors)
    except json.JSONDecodeError as error:
        print(f'monitorsgen: invalid JSON: {error}', file=sys.stderr)
        return EXIT_INVALID
    except SpecError as error:
        print(f'monitorsgen: {error}', file=sys.stderr)
        return EXIT_INVALID
    if args.print:
        sys.stdout.write(content)
        return 0
    target: Path = args.output
    try:
        if target.is_symlink() or (target.exists() and not target.is_file()):
            print(f'monitorsgen: refusing non-regular target {target}', file=sys.stderr)
            return EXIT_UNMANAGED
        if target.exists() and not is_managed(target):
            if not args.force:
                print(f'monitorsgen: {target} is not managed by the settings app; use --force to back it up '
                      'and overwrite', file=sys.stderr)
                return EXIT_UNMANAGED
            print(f'monitorsgen: backed up {target} to {backup(target)}', file=sys.stderr)
        atomic_write(target, content)
    except OSError as error:
        print(f'monitorsgen: cannot write {target}: {error}', file=sys.stderr)
        return EXIT_IO
    return 0


if __name__ == '__main__':
    sys.exit(main())
