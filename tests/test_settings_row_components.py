"""Shared row components of the settings app, in the sandboxed harness.

Runs tests/harness/drivers/settings-row-components.qml with the fake hyprctl
and checks its reports: the Quick page's power mode drop-down shows the
selected option (also after its options are rebuilt), "Requires «…»" chips
wrap instead of eliding at 760 px, the modified dot and the "?" follow the
last line of a wrapped label, sliders use the locale's decimal separator like
the window preview's magnifier, and the two previews of the Windows page have
their own accessible names and descriptions. See the driver for the steps.
"""
from __future__ import annotations

import json
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RUN = ROOT / "scripts/settings-harness/run.sh"
DRIVER = ROOT / "tests/harness/drivers/settings-row-components.qml"
MARKER = "[harness:report] "

EXPECTED_CHECKS = (
    "quick-select: power mode shows the selected option",
    "quick-select: every select row shows its selected option",
    "quick-select: rebuilt options keep the selected option",
    "requires-chip: windows: the chip shows the whole name at 760 px",
    "requires-chip: input: the chip shows the whole name at 760 px",
    "requires-chip: appearance: the chip shows the whole name at 760 px",
    "modified-dot: windows: decorations follow the last line of a wrapped label",
    "modified-dot: appearance: decorations follow the last line of a wrapped label",
    "modified-dot: wrapped labels with decorations found",
    "decimals: the slider uses the locale's decimal separator",
    "decimals: the slider and the magnifier show the same number",
    "decimals: no group separator",
    "preview-a11y: two previews with different accessible names",
    "preview-a11y: the effects preview describes blur, shadow, opacity and dimming",
    "preview-a11y: a single blur pass is not written as a plural",
    "preview-a11y: the layout preview still describes gaps, border and radius",
)


class SettingsRowComponentsTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        with tempfile.TemporaryDirectory() as out:
            cls.result = subprocess.run(
                ["bash", str(RUN), "--driver", str(DRIVER), "--renderer", "software", "--hyprland-stub",
                 "--strict", "--out", out, "--timeout", "150"],
                capture_output=True, text=True, timeout=240,
            )
            log_path = Path(out) / "harness.log"
            cls.log = log_path.read_text(encoding="utf-8", errors="replace") if log_path.is_file() else ""
        cls.events = [json.loads(line[line.index(MARKER) + len(MARKER):])
                      for line in cls.log.splitlines() if MARKER in line]

    def setUp(self) -> None:
        if self.result.returncode == 77:
            self.skipTest(self.result.stderr.strip() or "harness prerequisites missing")

    def context(self) -> str:
        return self.result.stdout + self.log[-3000:]

    def test_driver_checks_pass(self) -> None:
        self.assertFalse([e for e in self.events if e.get("type") == "fatal"], self.context())
        checks = [e for e in self.events if e.get("type") == "check"]
        names = {check["name"] for check in checks}
        for expected in EXPECTED_CHECKS:
            self.assertIn(expected, names, self.context())
        for check in checks:
            with self.subTest(check=check["name"]):
                self.assertTrue(check["ok"], check)
        self.assertEqual([e.get("failures") for e in self.events if e.get("type") == "done"], [0], self.context())
        # --strict: no QML warning.
        self.assertEqual(self.result.returncode, 0, self.context())


if __name__ == "__main__":
    unittest.main()
