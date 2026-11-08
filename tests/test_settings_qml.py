"""QML unit tests of the settings core (tests/qml_settings) with Qt 6 qmltestrunner."""
from __future__ import annotations

import os
from pathlib import Path
import subprocess
import unittest


ROOT = Path(__file__).resolve().parents[1]
# /usr/bin/qmltestrunner is the Qt 5 binary and silently exits 1 on Qt 6 tests.
QMLTESTRUNNER = Path("/usr/lib/qt6/bin/qmltestrunner")


class SettingsQmlTest(unittest.TestCase):
    def test_settings_core(self) -> None:
        if not QMLTESTRUNNER.is_file():
            self.skipTest(f"Qt 6 qmltestrunner not found at {QMLTESTRUNNER}")
        result = subprocess.run(
            [str(QMLTESTRUNNER), "-input", str(ROOT / "tests/qml_settings")],
            # File reads let the fixture-driven tests (AnimationLogic parity cases,
            # CurveMath golden values) run here instead of skipping.
            env={**os.environ, "QT_QPA_PLATFORM": "offscreen", "QT_QUICK_CONTROLS_STYLE": "Basic",
                 "QML_XHR_ALLOW_FILE_READ": "1"},
            capture_output=True, text=True, timeout=120,
        )
        output = result.stdout + result.stderr
        self.assertEqual(result.returncode, 0, output)
        self.assertIn(", 0 failed", output)
        self.assertIn(", 0 skipped", output)


if __name__ == "__main__":
    unittest.main()
