"""StyledSpinBox applies typed text once, clamped, never NaN (sandboxed harness)."""
from __future__ import annotations

import json
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RUN = ROOT / "scripts/settings-harness/run.sh"
DRIVER = ROOT / "tests/harness/drivers/spinbox-typed-commit.qml"
MARKER = "[harness:report] "


class SpinBoxTypedCommitTest(unittest.TestCase):
    def test_typed_text_commits_once_and_is_clamped(self) -> None:
        with tempfile.TemporaryDirectory() as out:
            result = subprocess.run(
                ["bash", str(RUN), "--driver", str(DRIVER), "--renderer", "software",
                 "--out", out, "--timeout", "90"],
                capture_output=True, text=True, timeout=150,
            )
            if result.returncode == 77:
                self.skipTest(result.stderr.strip() or "harness prerequisites missing")
            log = (Path(out) / "harness.log").read_text(encoding="utf-8", errors="replace")
        events = [json.loads(line[line.index(MARKER) + len(MARKER):])
                  for line in log.splitlines() if MARKER in line]
        self.assertFalse([e for e in events if e.get("type") == "fatal"], log[-2000:])
        steps = [event for event in events if event.get("type") == "spin"]
        self.assertEqual(len(steps), 7, result.stdout + log[-2000:])
        for step in steps:
            self.assertEqual(step["actual"], step["expected"], step)
        self.assertEqual(result.returncode, 0, result.stdout + log[-2000:])


if __name__ == "__main__":
    unittest.main()
