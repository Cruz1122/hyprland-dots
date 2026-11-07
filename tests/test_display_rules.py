from __future__ import annotations

import os
import shutil
import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RULES = ROOT / 'config/quickshell/ii/modules/common/functions/DisplayRules.js'
PANEL = ROOT / 'config/quickshell/ii/modules/common/displayControl/DisplayControl.qml'
QT_TEST_RUNNER = shutil.which('qmltestrunner6') or next(
    (str(path) for path in (Path('/usr/lib/qt6/bin/qmltestrunner'), Path('/usr/lib64/qt6/bin/qmltestrunner'))
     if path.is_file()), None)


class DisplayRulesTests(unittest.TestCase):
    def test_library_is_pure_and_used_by_display_control(self) -> None:
        source = RULES.read_text()
        self.assertTrue(source.startswith('.pragma library\n'))
        for forbidden in ('import ', 'Qt.', 'Process', 'hyprctl'):
            self.assertNotIn(forbidden, source.replace('`hyprctl eval`', ''))
        panel = PANEL.read_text()
        self.assertIn('import "../functions/DisplayRules.js" as DisplayRules', panel)
        for name in ('quoteLua', 'modeFor', 'monitorRule'):
            self.assertIn(f'return DisplayRules.{name}(', panel)

    @unittest.skipUnless(QT_TEST_RUNNER, 'Qt 6 Quick Test is not installed')
    def test_behavior_with_qt_javascript_engine(self) -> None:
        assert QT_TEST_RUNNER is not None
        environment = {**os.environ, 'QT_QUICK_BACKEND': 'software'}
        result = subprocess.run(
            [QT_TEST_RUNNER, '-input', str(ROOT / 'tests/qml/tst_DisplayRules.qml'), '-platform', 'offscreen'],
            capture_output=True, text=True, timeout=60, env=environment)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('Totals: 5 passed, 0 failed', result.stdout)


if __name__ == '__main__':
    unittest.main()
