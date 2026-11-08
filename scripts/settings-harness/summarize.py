#!/usr/bin/env python3
"""Turn a settings harness log into report.json and a pass/fail verdict.

The QML driver logs one "[harness:report] <json>" line per event. This script
collects them, separates app warnings from known sandbox noise, attributes
each warning to the page being visited, and compares config.json before and
after the run (loading pages must never write the config), as well as the
sha256 manifests run.sh takes of hypr/custom/* and hypr/monitors.lua.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any

REPORT_MARKER = "[harness:report] "
WARNING_PATTERN = re.compile(r"^\s*(WARN|ERROR|CRIT|CRITICAL|FATAL)\b")


def load_known(path: Path) -> list[re.Pattern[str]]:
    patterns = []
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if line and not line.startswith("#"):
            patterns.append(re.compile(line))
    return patterns


def flatten(value: Any, prefix: str = "") -> dict[str, Any]:
    if isinstance(value, dict):
        items: dict[str, Any] = {}
        for key, child in value.items():
            items.update(flatten(child, f"{prefix}.{key}" if prefix else str(key)))
        return items
    return {prefix: value}


def config_changes(before: Path | None, after: Path | None) -> dict[str, Any]:
    if before is None or after is None or not before.exists() or not after.exists():
        return {"checked": False}
    raw_before = before.read_bytes()
    raw_after = after.read_bytes()
    if raw_before == raw_after:
        return {"checked": True, "rewritten": False, "changed": []}
    try:
        old = flatten(json.loads(raw_before))
        new = flatten(json.loads(raw_after))
    except json.JSONDecodeError as error:
        return {"checked": True, "rewritten": True, "changed": [], "error": f"invalid JSON: {error}"}
    changed = []
    for key in sorted(old.keys() | new.keys()):
        if old.get(key, "<missing>") != new.get(key, "<missing>"):
            changed.append({"key": key, "before": old.get(key, "<missing>"), "after": new.get(key, "<missing>")})
    return {"checked": True, "rewritten": True, "changed": changed}


def hypr_changes(before: Path | None, after: Path | None) -> dict[str, Any]:
    """Compares two {relative path: sha256} manifests of the sandbox's Hyprland files."""
    if before is None or after is None or not before.exists() or not after.exists():
        return {"checked": False}
    old = json.loads(before.read_text(encoding="utf-8"))
    new = json.loads(after.read_text(encoding="utf-8"))
    written = sorted(path for path in new if old.get(path) != new[path])
    removed = sorted(path for path in old if path not in new)
    return {"checked": True, "written": written, "removed": removed}


def parse_log(log: Path, known: list[re.Pattern[str]]) -> dict[str, Any]:
    events: list[dict[str, Any]] = []
    app_warnings: list[dict[str, str]] = []
    env_warnings = 0
    context = "startup"
    for line in log.read_text(encoding="utf-8", errors="replace").splitlines():
        marker = line.find(REPORT_MARKER)
        if marker >= 0:
            try:
                event = json.loads(line[marker + len(REPORT_MARKER):])
            except json.JSONDecodeError:
                app_warnings.append({"context": context, "line": f"unparseable report: {line}"})
                continue
            events.append(event)
            if event.get("type") == "visit":
                context = f"{event.get('size')}/{event.get('name')}"
            continue
        if not WARNING_PATTERN.match(line):
            continue
        if any(pattern.search(line) for pattern in known):
            env_warnings += 1
            continue
        app_warnings.append({"context": context, "line": line.strip()})
    return {"events": events, "app_warnings": app_warnings, "env_warnings": env_warnings}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--log", type=Path, required=True)
    parser.add_argument("--known", type=Path, required=True)
    parser.add_argument("--config-before", type=Path)
    parser.add_argument("--config-after", type=Path)
    parser.add_argument("--hypr-before", type=Path, help="run.sh manifest of hypr/custom/* and hypr/monitors.lua")
    parser.add_argument("--hypr-after", type=Path)
    parser.add_argument("--out", type=Path, required=True, help="report.json destination")
    parser.add_argument("--exit-code", type=int, default=0, help="exit status of the app process")
    parser.add_argument("--strict", action="store_true", help="fail on warnings, layout findings and config writes")
    parser.add_argument("--allow-config-writes", action="store_true",
                        help="report config.json and hypr/custom writes as a note instead of a strict failure"
                             " (interaction drivers)")
    parser.add_argument("--hyprctl-log", type=Path,
                        help="hyprctl.log of a --hyprland-stub run: with --strict, the stub must have answered"
                             " '-j descriptions' and no captured page may show unavailable Hyprland or animation"
                             " rows")
    args = parser.parse_args()

    parsed = parse_log(args.log, load_known(args.known))
    events = parsed["events"]
    pages = [event for event in events if event.get("type") == "page"]
    fatal = [event for event in events if event.get("type") == "fatal"]
    done = any(event.get("type") == "done" for event in events)
    config = config_changes(args.config_before, args.config_after)
    hypr = hypr_changes(args.hypr_before, args.hypr_after)

    problems: list[str] = []
    if args.exit_code != 0:
        problems.append(f"app exited with status {args.exit_code} (124 means timeout)")
    for event in fatal:
        problems.append(f"fatal: {event.get('message')}")
    if not done:
        problems.append("driver never reported completion")
    unsaved = [page["file"] for page in pages if not page.get("saved")]
    if unsaved:
        problems.append(f"{len(unsaved)} screenshot(s) not saved")

    strict_problems: list[str] = []
    if parsed["app_warnings"]:
        strict_problems.append(f"{len(parsed['app_warnings'])} app warning(s)")
    for page in pages:
        where = f"{page.get('size')}/{page.get('name')}"
        if page.get("overlaps"):
            strict_problems.append(f"{where}: {len(page['overlaps'])} overlapping row pair(s)")
        if page.get("overflowX"):
            strict_problems.append(f"{where}: {len(page['overflowX'])} row(s) overflow horizontally")
        if page.get("openPopups", 0) > 0:
            strict_problems.append(f"{where}: {page['openPopups']} popup(s) open after load")
        # The stub stands in for Hyprland, so its two backends must be up.
        unavailable = page.get("unavailable") or {}
        for backend, what in (("hyprland", "Hyprland"), ("animation", "animation")):
            down = unavailable.get(backend, 0)
            if args.hyprctl_log is not None and down:
                strict_problems.append(f"{where}: {down} {what} row(s) unavailable with the Hyprland stub")
    if args.hyprctl_log is not None:
        calls = args.hyprctl_log.read_text(encoding="utf-8").splitlines() if args.hyprctl_log.exists() else []
        if not any(call.split() == ["-j", "descriptions"] for call in calls):
            strict_problems.append("the Hyprland stub never answered '-j descriptions' (see hyprctl.log)")
    if config.get("rewritten") and not args.allow_config_writes:
        strict_problems.append(f"config.json written during the run ({len(config.get('changed', []))} key(s) changed)")
    hypr_writes = [f"unexpected write to {path}" for path in hypr.get("written", [])]
    hypr_writes += [f"unexpected removal of {path}" for path in hypr.get("removed", [])]
    if not args.allow_config_writes:
        strict_problems.extend(hypr_writes)

    report = {
        "ok": not problems and (not args.strict or not strict_problems),
        "problems": problems,
        "strictProblems": strict_problems,
        "strict": args.strict,
        "pages": pages,
        "appWarnings": parsed["app_warnings"],
        "envWarnings": parsed["env_warnings"],
        "config": config,
        "hyprConfig": hypr,
    }
    args.out.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    print(f"pages captured: {len(pages)}")
    print(f"app warnings: {len(parsed['app_warnings'])} (sandbox noise ignored: {parsed['env_warnings']})")
    for warning in parsed["app_warnings"][:40]:
        print(f"  [{warning['context']}] {warning['line']}")
    if len(parsed["app_warnings"]) > 40:
        print(f"  ... {len(parsed['app_warnings']) - 40} more in {args.out}")
    for page in pages:
        flags = []
        if page.get("overlaps"):
            flags.append(f"overlaps={len(page['overlaps'])}")
        if page.get("overflowX"):
            flags.append(f"overflowX={len(page['overflowX'])}")
        if page.get("openPopups", 0) > 0:
            flags.append(f"popups={page['openPopups']}")
        print(f"  {page.get('size'):>9} {page.get('name'):<28} rows={page.get('rows', 0):<4} {' '.join(flags)}")
    if config.get("rewritten"):
        print(f"config.json was written; {len(config.get('changed', []))} key(s) changed:")
        for change in config.get("changed", [])[:20]:
            print(f"  {change['key']}: {change['before']!r} -> {change['after']!r}")
    if args.allow_config_writes:
        for note in hypr_writes:
            print(f"NOTE: {note}")
    for problem in problems:
        print(f"FAIL: {problem}")
    for problem in strict_problems:
        print(f"{'FAIL' if args.strict else 'NOTE'}: {problem}")
    return 0 if report["ok"] else 1


if __name__ == "__main__":
    sys.exit(main())
