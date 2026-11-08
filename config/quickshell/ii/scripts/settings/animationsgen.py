#!/usr/bin/env python3
"""Generate ~/.config/hypr/custom/shell-animations.lua for the settings app.

The file holds the Hyprland animations and curves the settings app manages
(docs/settings.md, "Backends -> animation"). This script is the only place
that turns those values into Lua: every value is re-validated against an
allowlist before it is written or sent to `hyprctl eval`.

Usage:
    animationsgen.py [--file PATH] --list --json
    animationsgen.py [--file PATH] --apply-json FILE|- [--eval]

--list --json prints the managed state:
    {"ok", "exists", "cards": {card: value}, "leaves": {leaf: value},
     "curves": {name: descriptor}, "appCurves": [name], "errors": [text]}
--apply-json reads a change set (a file, or stdin with "-"):
    {"cards": {card: value | null}, "curves": {name: descriptor | null},
     "removeAllAnimations": bool, "base": <hyprbase.py --json output>}
    null removes a card's lines or deletes a user curve. With --eval the changed
    statements (curves first) are applied with one `hyprctl eval` before the
    file is written; when Hyprland rejects them, `hyprctl reload config-only`
    puts the live state back to the files and nothing is written.
    It prints one JSON object {"ok", "changed", "written", "evalOk", "reloaded",
    "errors", "cards"}.

Card value: {"enabled": bool, "speed": number in (0, 100], "curve": name, "style": text}.
Curve descriptor: {"type": "bezier", "points": [x1, y1, x2, y2], "label": text} or
{"type": "spring", "mass", "stiffness", "damping", "label"}.

Exit codes: 0 ok; 2 usage or validation error (nothing applied or written);
3 the file exists but was not written by this script (never overwritten);
4 hyprctl eval failed (compensated with a reload, nothing written);
5 the file could not be read or written.
"""
from __future__ import annotations

import argparse
import decimal
import json
import math
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any

MARKER = '-- managed by the settings app (scripts/settings/animationsgen.py); manual edits are overwritten'
NOTE = '-- Generated file: Hyprland animations and curves chosen in the settings app (loaded by hyprland.lua).'
LABEL_PREFIX = '-- ii:curve '
EXIT_INVALID, EXIT_FOREIGN, EXIT_EVAL, EXIT_IO = 2, 3, 4, 5
HYPRCTL_TIMEOUT = 10

# card id -> (primary leaf, companion fade leaf or None, style family).
# Keep in sync with CARDS in modules/settings/backends/AnimationLogic.js.
CARDS: dict[str, tuple[str, str | None, str]] = {
    'windowsIn': ('windowsIn', 'fadeIn', 'windows'),
    'windowsOut': ('windowsOut', 'fadeOut', 'windows'),
    'windowsMove': ('windowsMove', None, 'windows'),
    'workspaces': ('workspaces', None, 'workspaces'),
    'specialWorkspaceIn': ('specialWorkspaceIn', None, 'workspaces'),
    'specialWorkspaceOut': ('specialWorkspaceOut', None, 'workspaces'),
    'layersIn': ('layersIn', 'fadeLayersIn', 'layers'),
    'layersOut': ('layersOut', 'fadeLayersOut', 'layers'),
    'border': ('border', None, 'none'),
    'zoomFactor': ('zoomFactor', None, 'none'),
}
LEAF_FAMILY = {leaf: family for leaf, _, family in CARDS.values()}
LEAF_FAMILY.update({companion: 'none' for _, companion, _ in CARDS.values() if companion})

# Hyprland 0.57 animation tree (src/config/shared/animation/AnimationTree.cpp).
PARENTS = {
    'windows': 'global', 'layers': 'global', 'fade': 'global', 'border': 'global',
    'borderangle': 'global', 'shadowangle': 'global', 'glowangle': 'global',
    'workspaces': 'global', 'zoomFactor': 'global', 'monitorAdded': 'global',
    'windowsIn': 'windows', 'windowsOut': 'windows', 'windowsMove': 'windows',
    'layersIn': 'layers', 'layersOut': 'layers',
    'fadeIn': 'fade', 'fadeOut': 'fade', 'fadeSwitch': 'fade', 'fadeShadow': 'fade', 'fadeGlow': 'fade',
    'fadeDim': 'fade', 'fadeLayers': 'fade', 'fadePopups': 'fade', 'fadeDpms': 'fade',
    'fadeLayersIn': 'fadeLayers', 'fadeLayersOut': 'fadeLayers',
    'fadePopupsIn': 'fadePopups', 'fadePopupsOut': 'fadePopups',
    'workspacesIn': 'workspaces', 'workspacesOut': 'workspaces', 'specialWorkspace': 'workspaces',
    'specialWorkspaceIn': 'specialWorkspace', 'specialWorkspaceOut': 'specialWorkspace',
}
# Nodes Hyprland's reset() overrides itself; every other node inherits.
COMPILED = {
    'global': {'enabled': True, 'speed': 8, 'curve': 'default', 'style': ''},
    'borderangle': {'enabled': False, 'speed': 1, 'curve': 'default', 'style': ''},
    'shadowangle': {'enabled': False, 'speed': 1, 'curve': 'default', 'style': ''},
    'glowangle': {'enabled': False, 'speed': 1, 'curve': 'default', 'style': ''},
}

BUILTIN_CURVES = {
    'default': {'type': 'bezier', 'points': [0, 0.75, 0.15, 1]},
    'linear': {'type': 'bezier', 'points': [0, 0, 1, 1]},
}
# Written as hl.curve lines only while a card uses them.
APP_SPRINGS = {
    'ii_spring_soft': {'type': 'spring', 'mass': 1, 'stiffness': 238.1191, 'damping': 24.21279333},
    'ii_spring_bouncy': {'type': 'spring', 'mass': 1, 'stiffness': 260, 'damping': 18},
}

IDENT_RE = re.compile(r'[A-Za-z_][A-Za-z0-9_]*')
USER_CURVE_RE = re.compile(r'ii_[a-z0-9_]{1,32}')
CONTROL_RE = re.compile('[\u0000-\u001f\u007f-\u009f\u2028\u2029]')
MAX_LABEL = 40
DIRECTIONS = ('top', 'bottom', 'left', 'right')
PERCENT_KINDS = {'windows': ('popin',), 'layers': ('popin',), 'workspaces': ('slidefade', 'slidefadevert')}
STYLE_KINDS = {
    'windows': ('slide', 'popin', 'gnomed'),
    'workspaces': ('slide', 'slidevert', 'fade', 'slidefade', 'slidefadevert'),
    'layers': ('fade', 'slide', 'popin'),
    'none': (),
}
CARD_FIELDS = {'enabled', 'speed', 'curve', 'style'}
CURVE_FIELDS = {'name', 'type', 'points', 'mass', 'stiffness', 'damping', 'label', 'group', 'builtin'}

NUM = r'-?\d+(?:\.\d+)?'
CURVE_LINE_RE = re.compile(
    r'hl\.curve\("(?P<name>[A-Za-z_][A-Za-z0-9_]*)", \{ (?:type = "bezier", points = \{ \{ (?P<x1>NUM), (?P<y1>NUM) \}, '
    r'\{ (?P<x2>NUM), (?P<y2>NUM) \} \}|type = "spring", mass = (?P<mass>NUM), stiffness = (?P<stiffness>NUM), '
    r'damping = (?P<damping>NUM)) \}\)'.replace('NUM', NUM))
ANIMATION_LINE_RE = re.compile(
    r'hl\.animation\(\{ leaf = "(?P<leaf>[A-Za-z]+)", enabled = (?P<enabled>true|false), speed = (?P<speed>NUM), '
    r'(?P<kind>bezier|spring) = "(?P<curve>[A-Za-z_][A-Za-z0-9_]*)"(?:, style = "(?P<style>[a-z0-9 %]*)")? \}\)'
    .replace('NUM', NUM))


class Invalid(ValueError):
    pass


class Foreign(Exception):
    pass


# ------------------------------------------------------------------ values

def is_number(value: object) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)


def round2(value: float) -> float:
    # floor(x * 100 + 0.5) / 100, the same expression as AnimationLogic.round2,
    # so both sides agree on halves (Python's round() rounds half to even).
    return math.floor(value * 100 + 0.5) / 100


def format_number(value: float) -> str:
    """Lua number literal without exponent: 1e-05 -> 0.00001, 3.0 -> 3."""
    if not is_number(value):
        raise Invalid(f'not a finite number: {value!r}')
    if float(value).is_integer():
        return str(int(value))
    text = format(decimal.Decimal(repr(float(value))), 'f')
    return text.rstrip('0').rstrip('.') if '.' in text else text


def check_label(label: object, where: str) -> str:
    if not isinstance(label, str) or not label.strip(' '):
        raise Invalid(f'{where}: the label must be a non-empty text')
    if CONTROL_RE.search(label):
        raise Invalid(f'{where}: the label contains control characters')
    if len(label) > MAX_LABEL:
        raise Invalid(f'{where}: the label is longer than {MAX_LABEL} characters')
    return label


def parse_style(family: str, style: str) -> dict[str, Any] | None:
    """{kind, percent, direction} for an allowlisted style of the family, else None."""
    if style == '':
        return {'kind': 'none', 'percent': None, 'direction': ''}
    words = style.split(' ')
    kind = words[0]
    if kind not in STYLE_KINDS.get(family, ()):
        return None
    percent, direction = None, ''
    rest = words[1:]
    if len(rest) > 1:
        return None
    if rest:
        arg = rest[0]
        if kind in PERCENT_KINDS.get(family, ()) and re.fullmatch(r'(0|[1-9][0-9]{0,2})%', arg):
            percent = int(arg[:-1])
            if percent > 100:
                return None
        elif kind == 'slide' and family in ('windows', 'layers') and arg in DIRECTIONS:
            direction = arg
        else:
            return None
    return {'kind': kind, 'percent': percent, 'direction': direction}


def check_style(family: str, style: object, where: str) -> str:
    if not isinstance(style, str) or parse_style(family, style) is None:
        raise Invalid(f'{where}: style {style!r} is not allowed here')
    return style


def check_speed(speed: object, where: str) -> float:
    if not is_number(speed) or not 0 < speed <= 100:
        raise Invalid(f'{where}: speed must be a number greater than 0 and at most 100')
    return speed


def check_curve_name(name: object, known: dict[str, dict], where: str) -> str:
    if not isinstance(name, str) or not IDENT_RE.fullmatch(name):
        raise Invalid(f'{where}: invalid curve name {name!r}')
    if name not in known:
        raise Invalid(f'{where}: unknown curve {name!r}')
    return name


def check_card_value(card: str, value: object, known: dict[str, dict]) -> dict[str, Any]:
    where = f'cards.{card}'
    if not isinstance(value, dict):
        raise Invalid(f'{where} must be an object or null')
    if set(value) != CARD_FIELDS:
        raise Invalid(f'{where} must have exactly the fields enabled, speed, curve and style')
    if not isinstance(value['enabled'], bool):
        raise Invalid(f'{where}: enabled must be true or false')
    return {
        'enabled': value['enabled'],
        'speed': check_speed(value['speed'], where),
        'curve': check_curve_name(value['curve'], known, where),
        'style': check_style(CARDS[card][2], value['style'], where),
    }


def check_curve(name: object, desc: object) -> dict[str, Any]:
    if not isinstance(name, str) or not USER_CURVE_RE.fullmatch(name):
        raise Invalid(f'curve name {name!r} must match ii_[a-z0-9_]{{1,32}}')
    if name in APP_SPRINGS:
        raise Invalid(f'{name} is one of the app curves and cannot be changed')
    where = f'curves.{name}'
    if not isinstance(desc, dict):
        raise Invalid(f'{where} must be an object or null')
    unknown = sorted(set(desc) - CURVE_FIELDS)
    if unknown:
        raise Invalid(f'{where} has unknown fields: {", ".join(unknown)}')
    if 'name' in desc and desc['name'] != name:
        raise Invalid(f'{where}: name does not match')
    label = check_label(desc.get('label'), where)
    kind = desc.get('type')
    if kind == 'bezier':
        if set(desc) & {'mass', 'stiffness', 'damping'}:
            raise Invalid(f'{where}: a bezier curve has no spring fields')
        points = desc.get('points')
        if not isinstance(points, list) or len(points) != 4 or not all(is_number(p) for p in points):
            raise Invalid(f'{where}: points must be four numbers [x1, y1, x2, y2]')
        x1, y1, x2, y2 = points
        if not (0 <= x1 <= 1 and 0 <= x2 <= 1):
            raise Invalid(f'{where}: x1 and x2 must be between 0 and 1')
        if not (-1 <= y1 <= 2 and -1 <= y2 <= 2):
            raise Invalid(f'{where}: y1 and y2 must be between -1 and 2')
        return {'name': name, 'type': 'bezier', 'points': list(points), 'label': label}
    if kind == 'spring':
        if 'points' in desc:
            raise Invalid(f'{where}: a spring has no points')
        out = {'name': name, 'type': 'spring', 'label': label}
        for field in ('mass', 'stiffness', 'damping'):
            value = desc.get(field)
            if not is_number(value) or not 0.5 < value <= 10000:
                raise Invalid(f'{where}: {field} must be a number greater than 0.5 and at most 10000')
            out[field] = value
        return out
    raise Invalid(f'{where}: type must be "bezier" or "spring"')


# --------------------------------------------------------------------- base

def check_base(base: object) -> dict[str, Any] | None:
    """Validated {curves, animations, errors} of a hyprbase.py result, or None when absent.

    A dotfiles curve whose name is not a Lua identifier cannot be written to
    the file, so it is left out (and reported in `errors`) instead of
    rejecting the whole base, which would block every card write. A base
    animation that uses such a curve is left out the same way."""
    if base is None:
        return None
    if not isinstance(base, dict):
        raise Invalid('base must be the JSON object printed by hyprbase.py --json')
    curves = base.get('curves', {})
    animations = base.get('animations', {})
    if not isinstance(curves, dict) or not isinstance(animations, dict):
        raise Invalid('base.curves and base.animations must be objects')
    out_curves: dict[str, dict] = {}
    errors: list[str] = []
    for name, desc in curves.items():
        if not IDENT_RE.fullmatch(name):
            errors.append(f'base.curves.{name} is not a Lua identifier; it is ignored')
            continue
        if not isinstance(desc, dict) or desc.get('type') not in ('bezier', 'spring'):
            raise Invalid(f'base.curves.{name} is not a valid curve')
        out_curves[name] = {'type': desc['type']}
    out_anims: dict[str, dict] = {}
    for leaf, item in animations.items():
        if leaf not in PARENTS and leaf != 'global':
            continue
        if not isinstance(item, dict) or not isinstance(item.get('enabled'), bool):
            raise Invalid(f'base.animations.{leaf} is not a valid animation')
        if not item['enabled'] and 'speed' not in item:
            out_anims[leaf] = {'enabled': False, 'speed': 1, 'curve': 'default', 'style': ''}
            continue
        curve = item.get('bezier', item.get('spring'))
        if not is_number(item.get('speed')) or not 0 < item['speed'] <= 100 or not isinstance(curve, str):
            raise Invalid(f'base.animations.{leaf} is not a valid animation')
        if not IDENT_RE.fullmatch(curve):
            # Uses an ignored curve: resolve() falls back to the parent or
            # Hyprland's compiled tuple for this leaf.
            errors.append(f'base.animations.{leaf} uses the ignored curve {curve}; it is ignored')
            continue
        style = item.get('style', '')
        if not isinstance(style, str):
            raise Invalid(f'base.animations.{leaf}.style must be text')
        out_anims[leaf] = {'enabled': item['enabled'], 'speed': item['speed'], 'curve': curve, 'style': style}
    return {'curves': out_curves, 'animations': out_anims, 'errors': errors}


def resolve(base: dict | None, leaf: str) -> dict[str, Any]:
    """Effective tuple of a leaf in the dotfiles base: nearest overridden ancestor."""
    node: str | None = leaf
    animations = base['animations'] if base else {}
    while node is not None:
        if node in animations:
            return dict(animations[node])
        if node in COMPILED:
            return dict(COMPILED[node])
        node = PARENTS.get(node)
    return dict(COMPILED['global'])


def companion_value(card: str, primary: dict[str, Any], base: dict | None, known: dict[str, dict]) -> dict[str, Any]:
    """Contracts §1: the fade companion follows the primary's enabled state and scales its base speed."""
    leaf, companion, _ = CARDS[card]
    assert companion is not None
    base_p = resolve(base, leaf)
    base_c = resolve(base, companion)
    if known.get(primary['curve'], {}).get('type') == 'spring' or base_p['speed'] <= 0:
        speed = base_c['speed']
    else:
        speed = min(100, max(0.01, round2(base_c['speed'] * primary['speed'] / base_p['speed'])))
    return {'enabled': primary['enabled'], 'speed': speed, 'curve': base_c['curve'], 'style': ''}


# --------------------------------------------------------------------- file

def parse_file(text: str) -> dict[str, Any]:
    """Managed state of a file this script wrote. Raises Foreign without the marker."""
    lines = text.splitlines()
    if not lines or lines[0] != MARKER:
        raise Foreign()
    curves: dict[str, dict] = {}
    labels: dict[str, str] = {}
    leaves: dict[str, dict] = {}
    kinds: dict[str, str] = {}
    errors: list[str] = []
    for number, line in enumerate(lines[1:], 2):
        stripped = line.strip()
        if stripped.startswith(LABEL_PREFIX):
            try:
                meta = json.loads(stripped[len(LABEL_PREFIX):])
                labels[meta['name']] = check_label(meta['label'], f'line {number}')
            except (ValueError, KeyError, TypeError) as error:
                errors.append(f'line {number}: unreadable curve label ({error})')
            continue
        if not stripped or stripped.startswith('--'):
            continue
        if match := CURVE_LINE_RE.fullmatch(stripped):
            name = match['name']
            if match['x1'] is not None:
                curves[name] = {'type': 'bezier',
                                'points': [float_or_int(match[k]) for k in ('x1', 'y1', 'x2', 'y2')]}
            else:
                curves[name] = {'type': 'spring', **{k: float_or_int(match[k]) for k in ('mass', 'stiffness', 'damping')}}
            continue
        if (match := ANIMATION_LINE_RE.fullmatch(stripped)) and match['leaf'] in LEAF_FAMILY:
            leaves[match['leaf']] = {'enabled': match['enabled'] == 'true', 'speed': float_or_int(match['speed']),
                                     'curve': match['curve'], 'style': match['style'] or ''}
            kinds[match['curve']] = match['kind']
            continue
        errors.append(f'line {number}: not written by animationsgen.py, it will be dropped on the next change')
    user = {name: {'name': name, **desc, 'label': labels.get(name, name)}
            for name, desc in curves.items() if USER_CURVE_RE.fullmatch(name) and name not in APP_SPRINGS}
    return {'curves': user, 'leaves': leaves, 'kinds': kinds, 'errors': errors}


def float_or_int(text: str) -> float | int:
    value = float(text)
    return int(value) if value.is_integer() and '.' not in text else value


def load(path: Path) -> tuple[str | None, dict[str, Any]]:
    if path.is_symlink() or (path.exists() and not path.is_file()):
        raise Foreign()
    if not path.exists():
        return None, {'curves': {}, 'leaves': {}, 'kinds': {}, 'errors': []}
    text = path.read_text(encoding='utf-8')
    return text, parse_file(text)


def cards_of(leaves: dict[str, dict]) -> dict[str, dict]:
    return {card: dict(leaves[leaf]) for card, (leaf, _, _) in CARDS.items() if leaf in leaves}


def curve_line(name: str, desc: dict[str, Any]) -> str:
    if desc['type'] == 'bezier':
        x1, y1, x2, y2 = (format_number(p) for p in desc['points'])
        return f'hl.curve("{name}", {{ type = "bezier", points = {{ {{ {x1}, {y1} }}, {{ {x2}, {y2} }} }} }})'
    return (f'hl.curve("{name}", {{ type = "spring", mass = {format_number(desc["mass"])}, '
            f'stiffness = {format_number(desc["stiffness"])}, damping = {format_number(desc["damping"])} }})')


def animation_line(leaf: str, value: dict[str, Any], known: dict[str, dict]) -> str:
    # Disabled leaves keep their full tuple: Hyprland accepts and ignores the
    # extra fields (live spike F1/D1), and the file stays the only place the
    # tuple survives, so enabling the card again restores it.
    kind = 'spring' if known[value['curve']]['type'] == 'spring' else 'bezier'
    parts = [f'leaf = "{leaf}"', f'enabled = {"true" if value["enabled"] else "false"}',
             f'speed = {format_number(value["speed"])}', f'{kind} = "{value["curve"]}"']
    if value['style']:
        parts.append(f'style = "{value["style"]}"')
    return 'hl.animation({ ' + ', '.join(parts) + ' })'


def render(user: dict[str, dict], leaves: dict[str, dict], known: dict[str, dict]) -> str:
    used = {value['curve'] for value in leaves.values()}
    lines = [MARKER, NOTE]
    curve_lines = []
    for name in sorted(user):
        label = json.dumps({'label': user[name]['label'], 'name': name}, ensure_ascii=True, sort_keys=True)
        curve_lines += [LABEL_PREFIX + label, curve_line(name, user[name])]
    curve_lines += [curve_line(name, APP_SPRINGS[name]) for name in sorted(APP_SPRINGS) if name in used]
    if curve_lines:
        lines += [''] + curve_lines
    animation_lines = []
    for leaf, companion, _ in CARDS.values():
        for name in (leaf, companion):
            if name and name in leaves:
                animation_lines.append(animation_line(name, leaves[name], known))
    if animation_lines:
        lines += [''] + animation_lines
    return '\n'.join(lines) + '\n'


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


# -------------------------------------------------------------------- apply

def known_curves(base: dict | None, user: dict[str, dict], carried: dict[str, str]) -> dict[str, dict]:
    known: dict[str, dict] = {name: dict(desc) for name, desc in BUILTIN_CURVES.items()}
    if base:
        known.update(base['curves'])
    else:
        # Without the base only names this script already wrote are trusted again.
        known.update({name: {'type': kind} for name, kind in carried.items() if IDENT_RE.fullmatch(name)})
    known.update({name: dict(desc) for name, desc in APP_SPRINGS.items()})
    known.update({name: {'type': desc['type']} for name, desc in user.items()})
    return known


def check_changes(raw: object) -> dict[str, Any]:
    if not isinstance(raw, dict):
        raise Invalid('the change set must be a JSON object')
    unknown = sorted(set(raw) - {'cards', 'curves', 'removeAllAnimations', 'base'})
    if unknown:
        raise Invalid(f'unknown change set fields: {", ".join(unknown)}')
    cards = raw.get('cards', {})
    curves = raw.get('curves', {})
    remove_all = raw.get('removeAllAnimations', False)
    if not isinstance(cards, dict) or not isinstance(curves, dict) or not isinstance(remove_all, bool):
        raise Invalid('cards and curves must be objects and removeAllAnimations a boolean')
    bad = sorted(card for card in cards if card not in CARDS)
    if bad:
        raise Invalid(f'unknown cards: {", ".join(map(str, bad))}')
    return {'cards': cards, 'curves': curves, 'removeAll': remove_all, 'base': check_base(raw.get('base'))}


def apply(state: dict[str, Any], raw: object) -> tuple[dict[str, dict], dict[str, dict], dict[str, dict], list[str]]:
    """New (user curves, leaves, known curves, non-fatal errors) after a change set; raises Invalid."""
    changes = check_changes(raw)
    base = changes['base']
    user = dict(state['curves'])
    deleted = []
    for name, desc in changes['curves'].items():
        if desc is None:
            if name in APP_SPRINGS or name in BUILTIN_CURVES or (base and name in base['curves']):
                raise Invalid(f'{name} is not one of your curves and cannot be deleted')
            if user.pop(name, None) is not None:
                deleted.append(name)
        else:
            user[name] = check_curve(name, desc)
    leaves = {} if changes['removeAll'] else {leaf: dict(v) for leaf, v in state['leaves'].items()}
    carried = {value['curve']: state['kinds'].get(value['curve'], 'bezier') for value in leaves.values()}
    known = known_curves(base, user, carried)
    for card, value in changes['cards'].items():
        leaf, companion, _ = CARDS[card]
        leaves.pop(leaf, None)
        if companion:
            leaves.pop(companion, None)
        if value is None:
            continue
        if base is None:
            raise Invalid('the dotfiles base (hyprbase.py) is required to change an animation')
        primary = check_card_value(card, value, known)
        leaves[leaf] = primary
        if companion:
            leaves[companion] = companion_value(card, primary, base, known)
    for name in deleted:
        users = [card for card, value in cards_of(leaves).items() if value['curve'] == name]
        if users:
            raise Invalid(f'curve {name} is used by: {", ".join(users)}')
    # Every line written is re-validated, the carried-over ones too.
    for leaf, value in leaves.items():
        where = f'leaf {leaf}'
        check_speed(value['speed'], where)
        check_curve_name(value['curve'], known, where)
        check_style(LEAF_FAMILY[leaf], value['style'], where)
    return user, leaves, known, list(base['errors']) if base else []


def statements(text: str) -> list[str]:
    return [line for line in text.splitlines() if line.startswith(('hl.curve(', 'hl.animation('))]


def hyprctl(*args: str) -> tuple[int, str]:
    try:
        result = subprocess.run(['hyprctl', *args], capture_output=True, text=True, timeout=HYPRCTL_TIMEOUT)
    except (OSError, subprocess.TimeoutExpired) as error:
        return 127, f'hyprctl {args[0]}: {error}'
    output = (result.stderr + result.stdout).strip()
    # Hyprland answers "ok"; binding errors come back as "error: ..." lines.
    if result.returncode == 0 and output.startswith('error'):
        return 1, output
    return result.returncode, output


def emit(result: dict[str, Any], code: int) -> int:
    print(json.dumps(result, ensure_ascii=False, sort_keys=True))
    return code


def cmd_list(path: Path) -> int:
    try:
        _, state = load(path)
    except Foreign:
        return emit({'ok': False, 'foreign': True, 'errors': [f'{path} was not written by the settings app']},
                    EXIT_FOREIGN)
    except (OSError, UnicodeDecodeError) as error:
        return emit({'ok': False, 'errors': [f'cannot read {path}: {error}']}, EXIT_IO)
    used = sorted({v['curve'] for v in state['leaves'].values() if v['curve'] in APP_SPRINGS})
    curves = {name: {**desc, 'group': 'user', 'builtin': False} for name, desc in sorted(state['curves'].items())}
    return emit({'ok': True, 'exists': path.exists(), 'cards': cards_of(state['leaves']), 'leaves': state['leaves'],
                 'curves': curves, 'appCurves': used, 'errors': state['errors']}, 0)


def cmd_apply(path: Path, source: str, do_eval: bool) -> int:
    result: dict[str, Any] = {'ok': False, 'changed': False, 'written': False, 'evalOk': None,
                              'reloaded': False, 'errors': [], 'cards': {}}
    try:
        raw = json.load(sys.stdin) if source == '-' else json.loads(Path(source).read_text(encoding='utf-8'))
    except (OSError, UnicodeDecodeError, ValueError) as error:
        result['errors'] = [f'invalid change set: {error}']
        return emit(result, EXIT_INVALID)
    try:
        old_text, state = load(path)
    except Foreign:
        result['errors'] = [f'{path} was not written by the settings app; it is never overwritten']
        return emit(result, EXIT_FOREIGN)
    except (OSError, UnicodeDecodeError) as error:
        result['errors'] = [f'cannot read {path}: {error}']
        return emit(result, EXIT_IO)
    try:
        user, leaves, known, warnings = apply(state, raw)
        text = render(user, leaves, known)
    except Invalid as error:
        result['errors'] = [str(error)]
        result['cards'] = cards_of(state['leaves'])
        return emit(result, EXIT_INVALID)
    result['cards'] = cards_of(leaves)
    # Non-fatal problems (ignored base curves); replaced by the error on a failure below.
    result['errors'] = warnings
    if text == old_text:
        result['ok'] = True
        return emit(result, 0)
    result['changed'] = True
    if do_eval:
        # Only new or changed statements can be applied live, curves first
        # (render() emits them first). Removed lines need the reload that
        # follows the write. Several statements in one eval are not atomic,
        # so any failure reloads the files to undo the part that applied.
        old = set(statements(old_text or ''))
        live = [line for line in statements(text) if line not in old]
        if live:
            code, output = hyprctl('eval', '; '.join(live))
            result['evalOk'] = code == 0
            if code != 0:
                result['errors'] = [output or f'hyprctl eval exited with {code}']
                reload_code, reload_output = hyprctl('reload', 'config-only')
                result['reloaded'] = reload_code == 0
                if reload_code != 0:
                    result['errors'].append(reload_output or f'hyprctl reload exited with {reload_code}')
                result['cards'] = cards_of(state['leaves'])
                return emit(result, EXIT_EVAL)
    try:
        atomic_write(path, text)
    except OSError as error:
        result['errors'] = [f'cannot write {path}: {error}']
        return emit(result, EXIT_IO)
    result['written'] = True
    result['ok'] = True
    return emit(result, 0)


def default_file() -> Path:
    config = os.environ.get('XDG_CONFIG_HOME') or str(Path.home() / '.config')
    return Path(config) / 'hypr/custom/shell-animations.lua'


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description='Generate the Hyprland animations file of the settings app.')
    parser.add_argument('--file', type=Path, default=None, help='target (default: $XDG_CONFIG_HOME/hypr/custom/'
                                                                 'shell-animations.lua)')
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument('--list', action='store_true', help='print the managed state')
    mode.add_argument('--apply-json', metavar='FILE', help='apply a change set from FILE, or stdin with "-"')
    parser.add_argument('--json', action='store_true', help='with --list: JSON output (the only format)')
    parser.add_argument('--eval', action='store_true', help='with --apply-json: apply live with hyprctl eval first')
    try:
        args = parser.parse_args(sys.argv[1:] if argv is None else argv)
    except SystemExit as error:
        return EXIT_INVALID if error.code else 0
    if args.list and (args.eval or not args.json):
        parser.print_usage(sys.stderr)
        print('animationsgen: --list needs --json and takes no --eval', file=sys.stderr)
        return EXIT_INVALID
    path = args.file if args.file is not None else default_file()
    if args.list:
        return cmd_list(path)
    return cmd_apply(path, args.apply_json, args.eval)


if __name__ == '__main__':
    sys.exit(main())
