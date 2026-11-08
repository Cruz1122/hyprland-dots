"""Closing the settings window finishes the backends' pending work first.

Backends apply changes through asynchronous commands. The window used to
revert a pending risky preview and quit at once, so the restore never ran (an
idle or display preview stayed applied) and writes still in their debounce or
held by the confirmation were dropped. See
tests/harness/drivers/close-finishes-work.qml (sandboxed harness, stub hyprctl).
"""
from __future__ import annotations

import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RUN = ROOT / "scripts/settings-harness/run.sh"
DRIVER = ROOT / "tests/harness/drivers/close-finishes-work.qml"
MARKER = "[harness:report] "

STUB = """#!/bin/sh
printf '%s\\n' "$*" >> "$HYPRCTL_LOG"
case "$*" in
    "-j descriptions") cat "$HYPRCTL_DESCRIPTIONS" ;;
    "-j devices") printf '{"mice": [], "keyboards": []}\\n' ;;
    "-j monitors"*) printf '[]\\n' ;;
    *) printf 'ok\\n' ;;
esac
"""

DESCRIPTIONS = [
    {"name": "input:kb_layout", "current": "latam", "default": "us"},
    {"name": "general:gaps_in", "current": 4, "default": 5},
]


def index_of(lines: list[str], predicate, start: int = 0) -> int:
    for i in range(start, len(lines)):
        if predicate(lines[i]):
            return i
    return -1


class SettingsCloseTest(unittest.TestCase):
    def test_close_reverts_the_preview_and_writes_held_changes_before_quitting(self) -> None:
        with tempfile.TemporaryDirectory() as out:
            bin_dir = Path(out) / "bin"
            bin_dir.mkdir()
            stub = bin_dir / "hyprctl"
            stub.write_text(STUB, encoding="utf-8")
            stub.chmod(0o755)
            log = Path(out) / "hyprctl.log"
            log.write_text("", encoding="utf-8")
            descriptions = Path(out) / "descriptions.json"
            descriptions.write_text(json.dumps(DESCRIPTIONS), encoding="utf-8")
            result = subprocess.run(
                ["bash", str(RUN), "--driver", str(DRIVER), "--renderer", "software",
                 "--out", out, "--timeout", "60",
                 "--env", f"PATH={bin_dir}:{os.environ.get('PATH', '/usr/bin:/bin')}",
                 "--env", "HYPRLAND_INSTANCE_SIGNATURE=settings-harness",
                 "--env", f"HYPRCTL_LOG={log}",
                 "--env", f"HYPRCTL_DESCRIPTIONS={descriptions}"],
                capture_output=True, text=True, timeout=120,
            )
            if result.returncode == 77:
                self.skipTest(result.stderr.strip() or "harness prerequisites missing")
            harness_log = (Path(out) / "harness.log").read_text(encoding="utf-8", errors="replace")
            calls = log.read_text(encoding="utf-8").splitlines()
        events = [json.loads(line[line.index(MARKER) + len(MARKER):])
                  for line in harness_log.splitlines() if MARKER in line]
        context = "\n".join(calls) + "\n" + harness_log[-2000:]
        self.assertFalse([e for e in events if e.get("type") == "fatal"], context)
        # Presenting the window again (IPC show/open/reveal) cancels the quit.
        self.assertIn({"type": "reopened", "visible": True}, events, context)
        self.assertIn({"type": "closed", "visible": False}, events, context)
        preview = index_of(calls, lambda c: c.startswith("eval ") and "kb_layout" in c and '"us"' in c)
        self.assertGreaterEqual(preview, 0, context)
        restore = index_of(calls, lambda c: c.startswith("eval ") and "kb_layout" in c and '"latam"' in c, preview + 1)
        self.assertGreater(restore, preview, "the preview is reverted before quitting\n" + context)
        # The fallback reload only follows a finished write of shell-settings.lua,
        # so it shows that the gaps change held by the confirmation was written.
        reload = index_of(calls, lambda c: c == "reload config-only", restore + 1)
        self.assertGreater(reload, restore, "the held write finishes before quitting\n" + context)
        # The app quit by itself (a timeout kill fails the harness run).
        self.assertEqual(result.returncode, 0, result.stdout + context)


if __name__ == "__main__":
    unittest.main()
