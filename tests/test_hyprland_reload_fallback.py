"""Hyprland override writes apply even when Hyprland does not watch the file yet.

Hyprland only watches custom/shell-settings.lua once its config has loaded
it, so the first override written on a fresh install never applied until
something else reloaded the config. The backend now reloads once
(`hyprctl reload config-only`) when no `configreloaded` follows a write.
See tests/harness/drivers/hyprland-reload-fallback.qml (sandboxed harness,
stub hyprctl).
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
DRIVER = ROOT / "tests/harness/drivers/hyprland-reload-fallback.qml"
MARKER = "[harness:report] "

STUB = """#!/bin/sh
printf '%s\\n' "$*" >> "$HYPRCTL_LOG"
case "$*" in
    "-j descriptions") cat "$HYPRCTL_DESCRIPTIONS" ;;
    "-j devices") printf '{"mice": [], "keyboards": []}\\n' ;;
    *) printf 'ok\\n' ;;
esac
"""


class HyprlandReloadFallbackTest(unittest.TestCase):
    def test_unwatched_write_reloads_once_and_autoreloaded_write_does_not(self) -> None:
        with tempfile.TemporaryDirectory() as out:
            bin_dir = Path(out) / "bin"
            bin_dir.mkdir()
            stub = bin_dir / "hyprctl"
            stub.write_text(STUB, encoding="utf-8")
            stub.chmod(0o755)
            log = Path(out) / "hyprctl.log"
            log.write_text("", encoding="utf-8")
            descriptions = Path(out) / "descriptions.json"
            descriptions.write_text(json.dumps([{"name": "general:gaps_in", "current": 4, "default": 5}]),
                                    encoding="utf-8")
            result = subprocess.run(
                ["bash", str(RUN), "--driver", str(DRIVER), "--renderer", "software",
                 "--out", out, "--timeout", "90",
                 "--env", f"PATH={bin_dir}:{os.environ.get('PATH', '/usr/bin:/bin')}",
                 "--env", "HYPRLAND_INSTANCE_SIGNATURE=settings-harness",
                 "--env", f"HYPRCTL_LOG={log}",
                 "--env", f"HYPRCTL_DESCRIPTIONS={descriptions}"],
                capture_output=True, text=True, timeout=150,
            )
            if result.returncode == 77:
                self.skipTest(result.stderr.strip() or "harness prerequisites missing")
            harness_log = (Path(out) / "harness.log").read_text(encoding="utf-8", errors="replace")
            calls = log.read_text(encoding="utf-8")
        events = [json.loads(line[line.index(MARKER) + len(MARKER):])
                  for line in harness_log.splitlines() if MARKER in line]
        self.assertFalse([e for e in events if e.get("type") == "fatal"], harness_log[-2000:])
        scenarios = {e["scenario"]: e for e in events if e.get("type") == "reload"}
        self.assertEqual(set(scenarios), {"unwatched", "autoreload"}, result.stdout + harness_log[-2000:])
        for name, event in scenarios.items():
            with self.subTest(scenario=name):
                self.assertEqual(event["actual"], event["expected"], calls)
        self.assertEqual(result.returncode, 0, result.stdout + harness_log[-2000:])


if __name__ == "__main__":
    unittest.main()
