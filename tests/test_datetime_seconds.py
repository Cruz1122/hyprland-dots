"""services/DateTime.qml passes "Show seconds" (time.secondPrecision) to the clock text.

tests/harness/drivers/datetime-seconds.qml runs the real DateTime singleton in
the sandboxed harness with config.json seeded with time.format "hh:mm" and
secondPrecision true, then turns seconds off and on again through
Config.options. The format rule itself (where the seconds go) is unit-tested
in tests/qml_settings/tst_TimeFormat.qml; this test pins the consumer wiring.
"""
from __future__ import annotations

import json
import re
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RUN = ROOT / "scripts/settings-harness/run.sh"
DRIVER = ROOT / "tests/harness/drivers/datetime-seconds.qml"
DEFAULT_CONFIG = ROOT / "config/illogical-impulse/config.json"
MARKER = "[harness:report] "
WITH_SECONDS = re.compile(r"^\d{2}:\d{2}:\d{2}$")
WITHOUT_SECONDS = re.compile(r"^\d{2}:\d{2}$")


class DateTimeSecondsTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            config = json.loads(DEFAULT_CONFIG.read_text(encoding="utf-8"))
            config.setdefault("time", {}).update({"format": "hh:mm", "secondPrecision": True})
            seed = Path(tmp) / "seed.json"
            seed.write_text(json.dumps(config), encoding="utf-8")
            out = Path(tmp) / "out"
            # The driver changes the config on purpose; strict mode still fails
            # on QML warnings.
            cls.result = subprocess.run(
                ["bash", str(RUN), "--driver", str(DRIVER), "--strict", "--allow-config-writes", "--config",
                 str(seed), "--timeout", "90", "--renderer", "software", "--out", str(out)],
                capture_output=True, text=True, timeout=150)
            log_path = out / "harness.log"
            log = log_path.read_text(encoding="utf-8", errors="replace") if log_path.exists() else ""
        if cls.result.returncode == 77:
            raise unittest.SkipTest(cls.result.stderr.strip() or "harness prerequisites missing")
        cls.events = [json.loads(line[line.index(MARKER) + len(MARKER):]) for line in log.splitlines()
                      if MARKER in line]
        cls.context = cls.result.stdout + cls.result.stderr + log[-3000:]

    def clock(self, label: str) -> dict:
        found = [e for e in self.events if e.get("type") == "clock" and e.get("label") == label]
        self.assertEqual(len(found), 1, self.context)
        state = found[0]
        # The lock screen always shows seconds; it must not mask the setting.
        self.assertFalse(state["screenLocked"], state)
        self.assertEqual(state["format"], "hh:mm", state)
        return state

    def test_run_passes_and_completes(self) -> None:
        self.assertFalse([e for e in self.events if e.get("type") == "fatal"], self.context)
        self.assertIn({"type": "done"}, self.events, self.context)
        self.assertEqual(self.result.returncode, 0, self.context)

    def test_show_seconds_adds_seconds_and_ticks_every_second(self) -> None:
        for label in ("seeded", "on"):
            with self.subTest(label):
                state = self.clock(label)
                self.assertTrue(state["secondPrecision"], state)
                self.assertRegex(state["time"], WITH_SECONDS)
                self.assertTrue(state["secondsPrecision"], state)

    def test_seconds_off_keeps_the_format(self) -> None:
        state = self.clock("off")
        self.assertFalse(state["secondPrecision"], state)
        self.assertRegex(state["time"], WITHOUT_SECONDS)
        self.assertTrue(state["minutesPrecision"], state)


if __name__ == "__main__":
    unittest.main()
