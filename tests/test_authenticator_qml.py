"""Headless component tests with a fake store; no keyring or live shell access."""
from __future__ import annotations

import os
from pathlib import Path
import shutil
import subprocess
import unittest


ROOT = Path(__file__).resolve().parents[1]


class AuthenticatorQmlTest(unittest.TestCase):
    def test_isolated_components_and_model(self) -> None:
        executable = shutil.which("qmltestrunner6") or "/usr/lib/qt6/bin/qmltestrunner"
        if not Path(executable).is_file():
            self.skipTest("Qt 6 qmltestrunner is unavailable; no live-desktop fallback")
        result = subprocess.run(
            [executable, "-input", str(ROOT / "tests/qml"),
             "-import", str(ROOT / "tests/qml/mocks")],
            env={**os.environ, "QT_QPA_PLATFORM": "offscreen",
                 "QT_QUICK_CONTROLS_STYLE": "Basic", "QSG_RHI_BACKEND": "software",
                 "QML_XHR_ALLOW_FILE_READ": "1"},
            capture_output=True, text=True, timeout=60,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
