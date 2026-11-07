from __future__ import annotations

import importlib.util
import os
import re
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / 'config/quickshell/ii/scripts/settings/idlegen.py'
spec = importlib.util.spec_from_file_location('idlegen', SCRIPT)
idlegen = importlib.util.module_from_spec(spec)
spec.loader.exec_module(idlegen)


def run(*args: str) -> subprocess.CompletedProcess:
    return subprocess.run([sys.executable, str(SCRIPT), *args], capture_output=True, text=True, timeout=30)


class IdlegenTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.target = Path(self.temp.name) / 'custom/shell-idle.conf'

    def test_never_is_header_only_and_matches_shipped_default(self) -> None:
        content = idlegen.render(0, 0, 0)
        self.assertTrue(content.startswith(idlegen.MARKER + '\n'))
        self.assertNotIn('listener {', content)
        self.assertEqual((ROOT / 'config/hypr/custom/shell-idle.conf').read_text(), content)

    def test_single_listeners(self) -> None:
        lock = idlegen.render(300, 0, 0)
        self.assertEqual(lock.count('listener {'), 1)
        self.assertIn('timeout = 300\n    on-timeout = loginctl lock-session\n', lock)
        dpms = idlegen.render(0, 600, 0)
        self.assertIn('on-timeout = hyprctl dispatch \'hl.dsp.dpms({ action = "disable" })\'', dpms)
        self.assertIn('on-resume = hyprctl dispatch \'hl.dsp.dpms({ action = "enable" })\'', dpms)
        suspend = idlegen.render(0, 0, 900)
        self.assertIn('timeout = 900\n    on-timeout = systemctl suspend || loginctl suspend\n', suspend)

    def test_all_listeners_in_order_and_commands_match_hypridle_examples(self) -> None:
        content = idlegen.render(300, 600, 900)
        self.assertEqual(content.count('listener {'), 3)
        self.assertLess(content.index('timeout = 300'), content.index('timeout = 600'))
        self.assertLess(content.index('timeout = 600'), content.index('timeout = 900'))
        conf = (ROOT / 'config/hypr/hypridle.conf').read_text()
        for command in (idlegen.LOCK_CMD, idlegen.DPMS_OFF_CMD, idlegen.DPMS_ON_CMD):
            self.assertIn(command, conf)
        self.assertIn(f'$suspend_cmd = {idlegen.SUSPEND_CMD}', conf)
        self.assertNotIn('#', content.split('\n', 2)[2])

    def test_equal_timeouts_and_skipped_zero_are_valid(self) -> None:
        idlegen.render(300, 300, 300)
        idlegen.render(600, 0, 300 * 3)
        idlegen.render(0, 900, 600 * 2)

    def test_ordering_errors(self) -> None:
        for values, message in (((600, 300, 0), 'lock timeout (600s) must not exceed dpms'),
                                ((0, 900, 600), 'dpms timeout (900s) must not exceed suspend'),
                                ((900, 0, 600), 'lock timeout (900s) must not exceed suspend')):
            with self.subTest(values=values), self.assertRaisesRegex(idlegen.IdleError, re.escape(message)):
                idlegen.render(*values)

    def test_range_and_type_errors(self) -> None:
        for values in ((29, 0, 0), (0, 86401, 0), (0, 0, -1), (True, 0, 0), (1.5, 0, 0)):
            with self.subTest(values=values), self.assertRaises(idlegen.IdleError):
                idlegen.render(*values)
        idlegen.render(30, 0, 86400)

    def test_cli_writes_atomically_and_deterministically(self) -> None:
        result = run('--lock', '300', '--suspend', '900', '--output', str(self.target))
        self.assertEqual(result.returncode, 0, result.stderr)
        first = self.target.read_bytes()
        self.assertEqual(first.decode(), idlegen.render(300, 0, 900))
        self.assertEqual(self.target.stat().st_mode & 0o777, 0o644)
        self.assertEqual(run('--lock', '300', '--suspend', '900', '--output', str(self.target)).returncode, 0)
        self.assertEqual(self.target.read_bytes(), first)
        self.assertEqual(sorted(p.name for p in self.target.parent.iterdir()), ['shell-idle.conf'])

    def test_failed_replace_keeps_old_file_and_removes_temp(self) -> None:
        idlegen.atomic_write(self.target, 'old\n')
        with mock.patch.object(idlegen.os, 'replace', side_effect=OSError('boom')):
            with self.assertRaises(OSError):
                idlegen.atomic_write(self.target, 'new\n')
        self.assertEqual(self.target.read_text(), 'old\n')
        self.assertEqual(len(list(self.target.parent.iterdir())), 1)

    def test_cli_print_and_invalid_exit_codes(self) -> None:
        printed = run('--print', '--dpms', '600')
        self.assertEqual(printed.returncode, 0)
        self.assertEqual(printed.stdout, idlegen.render(0, 600, 0))
        invalid = run('--lock', '900', '--dpms', '300', '--output', str(self.target))
        self.assertEqual(invalid.returncode, 2)
        self.assertIn('must not exceed', invalid.stderr)
        self.assertFalse(self.target.exists())
        self.assertEqual(run('--lock', 'abc', '--print').returncode, 2)

    def test_refuses_unmanaged_target_unless_forced(self) -> None:
        self.target.parent.mkdir(parents=True)
        self.target.write_text('listener {\n    timeout = 10\n}\n')
        refused = run('--lock', '300', '--output', str(self.target))
        self.assertEqual(refused.returncode, 3)
        self.assertIn('--force', refused.stderr)
        self.assertIn('timeout = 10', self.target.read_text())
        forced = run('--lock', '300', '--output', str(self.target), '--force')
        self.assertEqual(forced.returncode, 0, forced.stderr)
        self.assertEqual(self.target.read_text(), idlegen.render(300, 0, 0))

    def test_refuses_symlink_target(self) -> None:
        real = Path(self.temp.name) / 'real.conf'
        real.write_text(idlegen.render(0, 0, 0))
        self.target.parent.mkdir(parents=True)
        os.symlink(real, self.target)
        self.assertEqual(run('--output', str(self.target), '--force').returncode, 3)
        self.assertTrue(self.target.is_symlink())

    def test_hypridle_sources_generated_file_and_keeps_examples(self) -> None:
        conf = (ROOT / 'config/hypr/hypridle.conf').read_text()
        self.assertIn('\nsource = ~/.config/hypr/custom/shell-idle.conf\n', conf)
        self.assertEqual(conf.count('#listener {'), 3)
        self.assertIn('lock_cmd = $lock_cmd', conf)
        self.assertIn('inhibit_sleep = 3', conf)


if __name__ == '__main__':
    unittest.main()
