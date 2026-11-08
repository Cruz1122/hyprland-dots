"""Runs the pure-logic QML tests of the Sound, Applications and Region pages."""
from __future__ import annotations

import os
from pathlib import Path
import shutil
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]
TESTS = ["tst_MimeLogic.qml", "tst_AudioLogic.qml", "tst_AppsRegionLogic.qml"]


class SettingsS4LogicQmlTest(unittest.TestCase):
    def test_logic(self) -> None:
        executable = shutil.which("qmltestrunner6") or "/usr/lib/qt6/bin/qmltestrunner"
        if not Path(executable).is_file():
            self.skipTest("Qt 6 qmltestrunner is unavailable")
        for name in TESTS:
            with self.subTest(test=name):
                result = subprocess.run(
                    [executable, "-input", str(ROOT / "tests/qml_settings" / name)],
                    env={**os.environ, "QT_QPA_PLATFORM": "offscreen"},
                    capture_output=True, text=True, timeout=60,
                )
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn(", 0 failed", result.stdout)


if __name__ == "__main__":
    unittest.main()
