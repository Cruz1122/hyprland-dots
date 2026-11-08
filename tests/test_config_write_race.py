"""Config never drops a change because of its own file handling (sandboxed harness).

See tests/harness/drivers/config-write-race.qml for the two scenarios.
"""
from __future__ import annotations

import json
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RUN = ROOT / "scripts/settings-harness/run.sh"
DRIVER = ROOT / "tests/harness/drivers/config-write-race.qml"
MARKER = "[harness:report] "


class ConfigWriteRaceTest(unittest.TestCase):
    def test_reloads_and_writes_keep_every_change(self) -> None:
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
        races = {e["scenario"]: e for e in events if e.get("type") == "race"}
        self.assertEqual(set(races), {"reload", "inFlight"}, result.stdout + log[-2000:])
        for name, race in races.items():
            with self.subTest(scenario=name):
                self.assertEqual(race["memory"], race["expected"], race)
                self.assertEqual(race["disk"], race["expected"], race)
        self.assertEqual(result.returncode, 0, result.stdout + log[-2000:])


if __name__ == "__main__":
    unittest.main()
