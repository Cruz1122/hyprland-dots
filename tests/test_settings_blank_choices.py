"""Every drop-down shows a value and every segmented choice has one selected.

A stored value outside the choices left an empty box: Notifications > Monitor
showed nothing until a monitor was chosen. The driver visits every page of the
real settings window in the sandboxed harness with the default config; see
tests/harness/drivers/blank-choices.qml.
"""
from __future__ import annotations

import json
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RUN = ROOT / "scripts/settings-harness/run.sh"
DRIVER = ROOT / "tests/harness/drivers/blank-choices.qml"
MARKER = "[harness:report] "


class SettingsBlankChoicesTest(unittest.TestCase):
    def test_no_choice_control_is_blank(self) -> None:
        with tempfile.TemporaryDirectory() as out:
            result = subprocess.run(
                ["bash", str(RUN), "--driver", str(DRIVER), "--strict", "--renderer", "software",
                 "--out", out, "--timeout", "120"],
                capture_output=True, text=True, timeout=240,
            )
            if result.returncode == 77:
                self.skipTest(result.stderr.strip() or "harness prerequisites missing")
            harness_log = (Path(out) / "harness.log").read_text(encoding="utf-8", errors="replace")
        events = [json.loads(line[line.index(MARKER) + len(MARKER):])
                  for line in harness_log.splitlines() if MARKER in line]
        context = result.stdout + harness_log[-2000:]
        self.assertFalse([e for e in events if e.get("type") == "fatal"], context)
        self.assertEqual([e for e in events if e.get("type") == "blank"], [], context)
        self.assertIn({"type": "done"}, events, context)
        self.assertEqual(result.returncode, 0, context)


if __name__ == "__main__":
    unittest.main()
