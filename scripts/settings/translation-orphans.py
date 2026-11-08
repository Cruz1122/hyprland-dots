#!/usr/bin/env python3
"""List the keys of translations/es_MX.json that no source uses.

A key is used when it is:
  * a string literal passed to Translation.tr(...) in any .qml/.js file of the
    shell (config/quickshell/ii), main shell and settings app alike;
  * a registry text the settings app translates at runtime (docs/settings.md,
    "Registry schema"): pages.json group titles, page title and description,
    section title and description, entry label, description, note, help,
    minLabel, maxLabel, placeholder, actionLabel and unit, option label and
    description;
  * any string literal in the settings app's own .qml/.js sources
    (modules/settings): backends, core and components pass English messages
    around (unavailable reasons, errors, chip labels, preset names) and
    translate them later with Translation.tr(variable);
  * listed in the allowlist (translation-orphans-allowlist.txt next to this
    script): keys other code builds at runtime.

Matching is exact, like Translation.tr itself: "Saved" does not cover a
Translation.tr("Saved    ") call.

Usage: translation-orphans.py [--json] [--check] [--shell DIR]
                              [--translations FILE] [--allowlist FILE]
Exit codes: 0 report printed (or no orphans with --check), 1 orphans found
with --check, 2 usage or input error.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
DEFAULT_SHELL = REPO / "config/quickshell/ii"
DEFAULT_ALLOWLIST = Path(__file__).resolve().with_name("translation-orphans-allowlist.txt")

# JS/QML string literals: "…", '…' or a template literal without ${…}.
_DOUBLE = r'"((?:\\.|[^"\\\n])*)"'
_SINGLE = r"'((?:\\.|[^'\\\n])*)'"
_TEMPLATE = r"`((?:\\.|[^`\\$]|\$(?!\{))*)`"
TR_CALL = re.compile(r"Translation\.tr\(\s*(?:" + "|".join([_DOUBLE, _SINGLE, _TEMPLATE]) + r")\s*\)")
# One pattern per quote kind, scanned separately, so an apostrophe in a
# comment cannot pair with a later one and hide a "…" literal between them.
LITERALS = [re.compile(_DOUBLE), re.compile(_SINGLE), re.compile(_TEMPLATE)]

ENTRY_FIELDS = ("label", "description", "note", "help", "minLabel", "maxLabel", "placeholder", "actionLabel", "unit")
NOT_PAGES = {"pages.json", "retired.json"}
_ESCAPES = {"n": "\n", "t": "\t", "r": "\r", "b": "\b", "f": "\f", "v": "\v", "0": "\0"}
_ESCAPE = re.compile(r"\\(u\{[0-9A-Fa-f]+\}|u[0-9A-Fa-f]{4}|x[0-9A-Fa-f]{2}|.)", re.S)


class InputError(Exception):
    pass


def unescape(text: str) -> str:
    """Decode the JavaScript escapes of a literal's body."""
    def replace(match: re.Match[str]) -> str:
        code = match.group(1)
        if code.startswith("u{"):
            return chr(int(code[2:-1], 16))
        if len(code) > 1 and code[0] in "ux":
            return chr(int(code[1:], 16))
        return _ESCAPES.get(code, code)
    return _ESCAPE.sub(replace, text)


def literals(pattern: re.Pattern[str], text: str) -> set[str]:
    out = set()
    for match in pattern.finditer(text):
        body = next(group for group in match.groups() if group is not None)
        out.add(unescape(body))
    return out


def source_files(root: Path) -> list[Path]:
    if not root.is_dir():
        return []
    return sorted(p for p in root.rglob("*") if p.suffix in {".qml", ".js"} and p.is_file())


def read_json(path: Path):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:
        raise InputError(f"cannot read {path}: {exc}") from exc


def registry_strings(registry: Path) -> set[str]:
    out: set[str] = set()
    pages = registry / "pages.json"
    if pages.is_file():
        out |= {group.get("title", "") for group in read_json(pages).get("groups", [])}
    for path in sorted(registry.glob("*.json")):
        if path.name in NOT_PAGES:
            continue
        doc = read_json(path)
        out |= {doc.get("title", ""), doc.get("description", "")}
        for section in doc.get("sections", []):
            out |= {section.get("title", ""), section.get("description", "")}
        for entry in doc.get("entries", []):
            out |= {entry.get(field, "") for field in ENTRY_FIELDS}
            for option in entry.get("options", []):
                out |= {str(option.get("label", "")), option.get("description", "")}
    out.discard("")
    return {text for text in out if isinstance(text, str)}


def read_allowlist(path: Path) -> set[str]:
    """Each line is a JSON string followed by `# <code that builds it>`."""
    if not path.is_file():
        return set()
    keys = set()
    decoder = json.JSONDecoder()
    for number, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        try:
            key, end = decoder.raw_decode(line)
        except ValueError as exc:
            raise InputError(f"{path}:{number}: expected a JSON string: {exc}") from exc
        if not isinstance(key, str):
            raise InputError(f"{path}:{number}: expected a JSON string")
        if not re.match(r"\s*#\s*\S", line[end:]):
            raise InputError(f"{path}:{number}: add a `# comment` naming the code that builds this key")
        keys.add(key)
    return keys


def used_keys(shell: Path) -> set[str]:
    used: set[str] = set()
    settings = shell / "modules/settings"
    for path in source_files(shell):
        text = path.read_text(encoding="utf-8", errors="replace")
        used |= literals(TR_CALL, text)
        if settings in path.parents:
            for pattern in LITERALS:
                used |= literals(pattern, text)
    return used | registry_strings(settings / "registry")


def find_orphans(shell: Path, translations: Path, allowlist: Path) -> dict:
    keys = read_json(translations)
    if not isinstance(keys, dict):
        raise InputError(f"{translations} is not a JSON object")
    allowed = read_allowlist(allowlist)
    used = used_keys(shell)
    orphans = sorted(key for key in keys if key not in used and key not in allowed)
    return {
        "translations": str(translations),
        "keys": len(keys),
        "orphans": orphans,
        # Allowlisted keys that a source already covers, or that the file lacks.
        "staleAllowlist": sorted(key for key in allowed if key in used or key not in keys),
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--json", action="store_true", help="print the report as JSON")
    parser.add_argument("--check", action="store_true", help="exit 1 when there are orphans")
    parser.add_argument("--shell", type=Path, default=DEFAULT_SHELL, help="shell directory (config/quickshell/ii)")
    parser.add_argument("--translations", type=Path, help="translation file (default: <shell>/translations/es_MX.json)")
    parser.add_argument("--allowlist", type=Path, default=DEFAULT_ALLOWLIST, help="allowlist of runtime-built keys")
    args = parser.parse_args(argv)
    translations = args.translations or args.shell / "translations/es_MX.json"
    if not args.shell.is_dir():
        print(f"error: {args.shell} is not a directory", file=sys.stderr)
        return 2
    try:
        report = find_orphans(args.shell, translations, args.allowlist)
    except InputError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2
    if args.json:
        print(json.dumps(report, ensure_ascii=False, indent=2))
    else:
        print(f"{len(report['orphans'])} of {report['keys']} keys in {translations} are not used:")
        for key in report["orphans"]:
            print(json.dumps(key, ensure_ascii=False))
        for key in report["staleAllowlist"]:
            print(f"stale allowlist entry: {json.dumps(key, ensure_ascii=False)}", file=sys.stderr)
    return 1 if args.check and report["orphans"] else 0


if __name__ == "__main__":
    sys.exit(main())
