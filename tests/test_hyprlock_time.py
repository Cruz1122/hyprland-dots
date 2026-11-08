from __future__ import annotations

import os
from pathlib import Path
import stat
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "config/quickshell/ii/scripts/settings/hyprlock-time.py"
SAMPLE = "label {\n    text = $TIME12\n}\nlabel {\n    text = cmd[] echo $TIME $TIMEZONE\n}\n"


class HyprlockTimeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.file = self.root / "config/hypr/hyprlock.conf"
        self.file.parent.mkdir(parents=True)
        self.file.write_text(SAMPLE)
        self.env = {**os.environ, "HOME": str(self.root), "XDG_CONFIG_HOME": str(self.root / "config")}

    def tearDown(self):
        self.temp.cleanup()

    def run_cli(self, *args):
        return subprocess.run([sys.executable, str(SCRIPT), *args], capture_output=True, text=True, env=self.env, timeout=30)

    def test_switches_both_ways_without_touching_other_tokens(self):
        self.file.chmod(0o640)
        self.assertEqual(self.run_cli("24h").returncode, 0)
        self.assertEqual(self.file.read_text(), SAMPLE.replace("$TIME12", "$TIME"))
        self.assertEqual(stat.S_IMODE(self.file.stat().st_mode), 0o640)
        self.assertEqual(self.run_cli("12h").returncode, 0)
        self.assertEqual(self.file.read_text(),
                         "label {\n    text = $TIME12\n}\nlabel {\n    text = cmd[] echo $TIME12 $TIMEZONE\n}\n")
        self.assertEqual(self.run_cli("12h").returncode, 0)
        self.assertNotIn("$TIME1212", self.file.read_text())

    def test_writes_through_a_symlink(self):
        link = self.root / "link.conf"
        link.symlink_to(self.file)
        self.assertEqual(self.run_cli("24h", "--file", str(link)).returncode, 0)
        self.assertTrue(link.is_symlink())
        self.assertNotIn("$TIME12", self.file.read_text())

    def test_missing_file_is_not_an_error(self):
        self.file.unlink()
        result = self.run_cli("24h")
        self.assertEqual(result.returncode, 0)
        self.assertIn("does not exist", result.stderr)
        self.assertFalse(self.file.exists())

    def test_rejects_unknown_modes(self):
        for args in (("13h",), ("24h; rm -rf /",), ()):
            with self.subTest(args=args):
                result = self.run_cli(*args)
                self.assertEqual(result.returncode, 2)
        self.assertEqual(self.file.read_text(), SAMPLE)

    def test_unreadable_target_reports_io_error(self):
        result = self.run_cli("24h", "--file", str(self.root))
        self.assertEqual(result.returncode, 1)
        self.assertIn("error", result.stderr)


if __name__ == "__main__":
    unittest.main()
