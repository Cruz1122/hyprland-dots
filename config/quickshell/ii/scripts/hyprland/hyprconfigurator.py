#!/usr/bin/env -S\_/bin/sh\_-c\_"source\_\$(eval\_echo\_\$ILLOGICAL_IMPULSE_VIRTUAL_ENV)/bin/activate&&exec\_python\_-E\_"\$0"\_"\$@""
"""Edit a Lua file of Hyprland option overrides, one `hl.config({...})` per key.

Keys use `:` for nesting (`input:touchpad:tap_to_click`), and every segment must
be a Lua identifier. Lines the script does not manage (comments, other calls)
are preserved verbatim. Exit status is non-zero on any error, and the file is
never written partially.
"""
import argparse
import json
import os
import re
import sys
import tempfile
import unicodedata

EMPTY_SENTINEL = "[[EMPTY]]"
TYPES = ("bool", "int", "float", "string")

LUA_KEYWORDS = frozenset(
    "and break do else elseif end false for function goto if in local nil not "
    "or repeat return then true until while".split()
)
IDENT_RE = re.compile(r"[A-Za-z_][A-Za-z0-9_]*\Z")
INT_RE = re.compile(r"[+-]?[0-9]+\Z")
FLOAT_RE = re.compile(r"[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?\Z")
INT64_MIN, INT64_MAX = -(2**63), 2**63 - 1

# Line shapes written by this script (and by its earlier versions).
LINE_PREFIX_RE = re.compile(r"\s*hl\.config\(\{")
SEGMENT_RE = re.compile(r"\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*")
VALUE_RE = re.compile(
    r'(?P<bool>true|false)(?![A-Za-z0-9_])'
    r'|(?P<num>[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?)'
    r'|"(?P<str>(?:[^"\\\n]|\\.)*)"'
)
LUA_UNESCAPES = {"\\": "\\", '"': '"', "'": "'", "n": "\n", "t": "\t", "r": "\r"}


class ConfigError(Exception):
    pass


def validate_key(key):
    parts = key.split(":")
    for part in parts:
        if not IDENT_RE.match(part) or part in LUA_KEYWORDS:
            raise ConfigError(
                f"invalid key {key!r}: segment {part!r} is not a Lua identifier "
                "([A-Za-z_][A-Za-z0-9_]*, not a keyword); use '_' instead of '-'"
            )
    return parts


def reject_control_chars(text, what):
    for ch in text:
        if unicodedata.category(ch) in ("Cc", "Cs"):
            raise ConfigError(f"{what} contains a control character ({ch!r})")


def parse_typed(type_name, raw):
    """Convert a CLI string into a Python value of the requested type."""
    reject_control_chars(raw, "value")
    if type_name == "bool":
        if raw not in ("true", "false"):
            raise ConfigError(f"invalid bool {raw!r}: expected 'true' or 'false'")
        return raw == "true"
    if type_name == "int":
        if not INT_RE.match(raw):
            raise ConfigError(f"invalid int {raw!r}")
        value = int(raw)
        if not INT64_MIN <= value <= INT64_MAX:
            raise ConfigError(f"int {raw!r} is out of the 64-bit range")
        return value
    if type_name == "float":
        if not FLOAT_RE.match(raw):
            raise ConfigError(f"invalid float {raw!r}")
        return float(raw)
    if type_name == "string":
        return raw
    raise ConfigError(f"unknown type {type_name!r}; expected one of {', '.join(TYPES)}")


def infer_value(raw):
    """Legacy `--set` typing: booleans and numbers as-is, anything else a string."""
    if raw in ("true", "false"):
        return parse_typed("bool", raw)
    if INT_RE.match(raw):
        return parse_typed("int", raw)
    if FLOAT_RE.match(raw):
        return parse_typed("float", raw)
    return parse_typed("string", raw)


def lua_string(text):
    reject_control_chars(text, "value")
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'


def lua_value(value):
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, int):
        return str(value)
    if isinstance(value, float):
        if value != value or value in (float("inf"), float("-inf")):
            raise ConfigError(f"float {value!r} is not finite")
        return repr(value)
    return lua_string(value)


def config_line(parts, value):
    inner = f"{parts[-1]}={lua_value(value)}"
    for part in reversed(parts[:-1]):
        inner = f"{part}={{{inner}}}"
    return f"hl.config({{{inner}}})\n"


def unescape_lua(body):
    out = []
    i = 0
    while i < len(body):
        ch = body[i]
        if ch == "\\":
            nxt = body[i + 1]
            if nxt not in LUA_UNESCAPES:
                return None
            out.append(LUA_UNESCAPES[nxt])
            i += 2
        else:
            out.append(ch)
            i += 1
    return "".join(out)


def parse_line(line):
    """Return (key, value) for a managed line, (key, None) when the key is
    recognisable but the value is not (legacy unescaped strings), or None."""
    m = LINE_PREFIX_RE.match(line)
    if not m:
        return None
    pos = m.end()
    parts = []
    while True:
        seg = SEGMENT_RE.match(line, pos)
        if not seg:
            return None
        parts.append(seg.group(1))
        pos = seg.end()
        if line.startswith("{", pos):
            pos += 1
            continue
        break
    key = ":".join(parts)
    closers = r"\s*" + r"\}\s*" * len(parts) + r"\)\s*"
    val = VALUE_RE.match(line, pos)
    if not val or not re.fullmatch(closers, line[val.end():]):
        # Earlier versions wrote strings without escaping; such a line still
        # belongs to `key`. Anything else (several keys per call) is foreign.
        if re.fullmatch(r'".*"' + closers, line[pos:], re.S):
            return key, None
        return None
    if val.group("bool") is not None:
        return key, val.group("bool") == "true"
    if val.group("num") is not None:
        num = val.group("num")
        return key, int(num) if INT_RE.match(num) else float(num)
    text = unescape_lua(val.group("str"))
    return key, text


def read_lines(file_path):
    try:
        with open(file_path, "r", encoding="utf-8") as fh:
            return fh.readlines()
    except FileNotFoundError:
        return None
    except (OSError, UnicodeDecodeError) as exc:
        raise ConfigError(f"cannot read {file_path!r}: {exc}") from exc


def header_lines(text):
    lines = []
    for line in text.split("\n"):
        reject_control_chars(line, "header")
        lines.append(f"-- {line}".rstrip() + "\n")
    return lines


def apply_changes(lines, sets, resets, header):
    """Return the new file lines. `sets` is an ordered list of (key, value)."""
    is_new = not lines
    lines = list(lines or [])
    set_map = dict(sets)
    reset_keys = set(resets) - set(set_map)
    written = set()
    out = []
    for line in lines:
        parsed = parse_line(line)
        key = parsed[0] if parsed else None
        if key in reset_keys:
            continue
        if key in set_map:
            if key not in written:
                out.append(config_line(key.split(":"), set_map[key]))
                written.add(key)
            continue
        out.append(line)
    if out and not out[-1].endswith("\n"):
        out[-1] += "\n"
    for key, value in set_map.items():
        if key not in written:
            out.append(config_line(key.split(":"), value))
    if is_new and header is not None and out:
        out = header_lines(header) + out
    return out


def list_values(lines):
    result = {}
    for line in lines or []:
        parsed = parse_line(line)
        if not parsed:
            continue
        key, value = parsed
        if value is None:
            print(f"warning: unparsable value for {key!r}; skipped", file=sys.stderr)
            continue
        result[key] = value
    return result


def write_atomic(file_path, lines):
    dir_name = os.path.dirname(os.path.abspath(file_path))
    os.makedirs(dir_name, exist_ok=True)
    temp_path = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w", encoding="utf-8", dir=dir_name, delete=False,
            prefix=".hyprconfigurator-", suffix=".tmp",
        ) as temp_file:
            temp_path = temp_file.name
            temp_file.writelines(lines)
            temp_file.flush()
            os.fsync(temp_file.fileno())
        mode = os.stat(file_path).st_mode if os.path.exists(file_path) else 0o644
        os.chmod(temp_path, mode & 0o7777)
        os.replace(temp_path, file_path)
    except OSError as exc:
        if temp_path and os.path.exists(temp_path):
            os.remove(temp_path)
        raise ConfigError(f"cannot write {file_path!r}: {exc}") from exc


def build_parser():
    parser = argparse.ArgumentParser(
        description="Edit a Hyprland Lua override file. Subkeys use colon (:) for nesting."
    )
    parser.add_argument("--file", default="~/.config/hypr/hyprland.conf",
                        help="Path to the override file.")
    parser.add_argument("--set", nargs=2, action="append", metavar=("KEY", "VALUE"),
                        help="Set KEY; VALUE typed as bool/number when it looks like one, "
                             f"else string. {EMPTY_SENTINEL} removes KEY.")
    parser.add_argument("--set-typed", nargs=3, action="append",
                        metavar=("KEY", "TYPE", "VALUE"),
                        help=f"Set KEY with an explicit TYPE ({', '.join(TYPES)}).")
    parser.add_argument("--reset", action="append", metavar="KEY", help="Remove KEY.")
    parser.add_argument("--unset", action="append", metavar="KEY", help="Alias of --reset.")
    parser.add_argument("--list", action="store_true",
                        help="Print managed keys and typed values (requires --json).")
    parser.add_argument("--json", action="store_true", help="JSON output for --list.")
    parser.add_argument("--header", metavar="TEXT",
                        help="Comment header written only when the file is created.")
    return parser


def run(argv):
    args = build_parser().parse_args(argv)
    file_path = os.path.expanduser(args.file)
    reject_control_chars(file_path, "file path")

    if args.list:
        if args.set or args.set_typed or args.reset or args.unset:
            raise ConfigError("--list cannot be combined with --set/--set-typed/--reset/--unset")
        if not args.json:
            raise ConfigError("--list requires --json")
        print(json.dumps(list_values(read_lines(file_path)), sort_keys=True))
        return

    sets = []
    resets = []
    for key, raw in args.set or []:
        validate_key(key)
        if raw == EMPTY_SENTINEL:
            resets.append(key)
        else:
            sets.append((key, infer_value(raw)))
    for key, type_name, raw in args.set_typed or []:
        validate_key(key)
        sets.append((key, parse_typed(type_name, raw)))
    for key in (args.reset or []) + (args.unset or []):
        validate_key(key)
        resets.append(key)
    if not sets and not resets:
        raise ConfigError("must specify at least one key to set or reset")
    if args.header is not None:
        header_lines(args.header)

    old = read_lines(file_path)
    new = apply_changes(old, sets, resets, args.header)
    # Skipping identical writes avoids a needless Hyprland autoreload.
    if old is not None and new == old:
        return
    if old is None and not new:
        return
    write_atomic(file_path, new)
    for key in sorted(set(resets) - {k for k, _ in sets}):
        print(f"Removed '{key}' from '{file_path}'")
    for key, value in dict(sets).items():
        print(f"Updated '{file_path}' with {config_line(key.split(':'), value).strip()}")


def main(argv=None):
    try:
        run(sys.argv[1:] if argv is None else argv)
    except ConfigError as exc:
        print(f"hyprconfigurator: error: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
