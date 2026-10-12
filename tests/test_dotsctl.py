from __future__ import annotations

import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / 'scripts/dotsctl.py'
spec = importlib.util.spec_from_file_location('dotsctl', SCRIPT)
assert spec is not None and spec.loader is not None
dotsctl = importlib.util.module_from_spec(spec)
spec.loader.exec_module(dotsctl)


class DotsctlTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        self.repo = self.home / 'repo'
        self.live = self.home / '.config'
        self.state = self.home / '.local/state'
        for relative, data in {
            'hypr/hyprland.lua': '-- test\n',
            'quickshell/ii/shell.qml': 'import Quickshell\nShellRoot {}\n',
            'illogical-impulse/config.json': '{}\n',
            'hypr/custom/keybinds.lua': '-- source custom\n',
        }.items():
            self.write(self.repo / 'config' / relative, data)
        self.live.mkdir()
        self.env = {**os.environ, 'HOME': str(self.home), 'XDG_CONFIG_HOME': str(self.live),
                    'XDG_STATE_HOME': str(self.state), 'PYTHONDONTWRITEBYTECODE': '1'}

    def write(self, path, data):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(data)

    def run_action(self, action, *flags):
        return subprocess.run([sys.executable, str(SCRIPT), action, '--repo', str(self.repo), *flags],
                              env=self.env, text=True, capture_output=True)

    def require_ok(self, result):
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_install_requires_explicit_confirmation(self):
        result = self.run_action('install')
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.state.exists())
        self.assertEqual(list(self.live.iterdir()), [])

    def test_dry_run_changes_neither_files_nor_state(self):
        self.write(self.live / 'hypr/hyprland.lua', 'old')
        before = dotsctl.inventory(self.home)
        self.require_ok(self.run_action('install', '--dry-run'))
        self.assertEqual(dotsctl.inventory(self.home), before)
        self.assertFalse(self.state.exists())

    def test_backup_contains_old_content_before_overwrite(self):
        self.write(self.live / 'hypr/hyprland.lua', 'old')
        self.require_ok(self.run_action('install', '--yes'))
        backup, = (self.state / 'hyprland-dots/backups').iterdir()
        self.assertEqual((backup / 'config/hypr/hyprland.lua').read_text(), 'old')
        self.assertEqual(backup.stat().st_mode & 0o777, 0o700)
        dotsctl.verify_snapshot(backup)
        self.assertEqual((self.live / 'hypr/hyprland.lua').read_text(), '-- test\n')

    def test_backup_tampering_is_rejected(self):
        self.write(self.live / 'hypr/hyprland.lua', 'old')
        self.require_ok(self.run_action('install', '--yes'))
        backup, = (self.state / 'hyprland-dots/backups').iterdir()
        self.write(backup / 'config/hypr/hyprland.lua', 'tampered')
        result = self.run_action('verify-backup', '--backup', str(backup))
        self.assertNotEqual(result.returncode, 0)

    def test_existing_custom_and_settings_and_extra_files_are_preserved(self):
        self.write(self.live / 'hypr/custom/keybinds.lua', 'my custom')
        self.write(self.live / 'illogical-impulse/config.json', '{"mine": true}')
        self.write(self.live / 'hypr/extra.lua', 'live-only')
        self.require_ok(self.run_action('install', '--yes'))
        self.assertEqual((self.live / 'hypr/custom/keybinds.lua').read_text(), 'my custom')
        self.assertEqual(json.loads((self.live / 'illogical-impulse/config.json').read_text()), {'mine': True})
        self.assertEqual((self.live / 'hypr/extra.lua').read_text(), 'live-only')
        self.require_ok(self.run_action('install', '--yes', '--replace-user'))
        self.assertEqual((self.live / 'hypr/custom/keybinds.lua').read_text(), '-- source custom\n')

    def test_second_run_has_same_files_and_distinct_backups(self):
        self.require_ok(self.run_action('install', '--yes'))
        before = dotsctl.inventory(self.live)
        self.require_ok(self.run_action('install', '--yes'))
        self.assertEqual(dotsctl.inventory(self.live), before)
        self.assertEqual(len(list((self.state / 'hyprland-dots/backups').iterdir())), 2)

    def test_capture_prefers_live_and_preserves_repo_only_and_excludes_state(self):
        self.write(self.live / 'hypr/hyprland.lua', 'live new')
        self.write(self.live / 'hypr/new.lua', 'live-only')
        self.write(self.repo / 'config/hypr/repo-only.lua', 'work in progress')
        self.write(self.live / 'quickshell/ii/notes.json', 'private')
        self.require_ok(self.run_action('capture', '--yes'))
        self.assertEqual((self.repo / 'config/hypr/hyprland.lua').read_text(), 'live new')
        self.assertEqual((self.repo / 'config/hypr/new.lua').read_text(), 'live-only')
        self.assertEqual((self.repo / 'config/hypr/repo-only.lua').read_text(), 'work in progress')
        self.assertFalse((self.repo / 'config/quickshell/ii/notes.json').exists())
        backup, = (self.state / 'hyprland-dots/backups').iterdir()
        self.assertEqual((backup / 'config/hypr/hyprland.lua').read_text(), '-- test\n')

    def test_capture_dry_run_does_not_write(self):
        self.write(self.live / 'hypr/hyprland.lua', 'changed')
        before = dotsctl.inventory(self.home)
        self.require_ok(self.run_action('capture', '--dry-run'))
        self.assertEqual(dotsctl.inventory(self.home), before)

    def test_capture_dry_run_reports_single_file_entries(self):
        self.write(self.live / 'systemd/user/hyprland-session.target', '[Unit]\n')
        result = self.run_action('capture', '--dry-run')
        self.require_ok(result)
        self.assertIn('CAPTURE systemd/user/hyprland-session.target', result.stdout)
        self.assertFalse((self.repo / 'config/systemd').exists())

    def test_capture_then_install_renders_a_different_username(self):
        text = json.dumps({'savePath': str(self.home / 'Videos')})
        self.write(self.live / 'illogical-impulse/config.json', text)
        self.require_ok(self.run_action('capture', '--yes'))
        captured = (self.repo / 'config/illogical-impulse/config.json').read_bytes()
        self.assertIn(b'@HOME@/Videos', captured)
        other = self.home / 'another-user'
        self.assertIn(str(other / 'Videos').encode(), dotsctl.render(captured, other, other / '.config'))

    def test_external_source_symlink_fails_before_writes(self):
        external = self.home / 'outside'
        external.write_text('external')
        (self.repo / 'config/hypr/link').symlink_to(external)
        result = self.run_action('install', '--yes')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(list(self.live.iterdir()), [])
        self.assertFalse(self.state.exists())

    def test_destination_parent_symlink_cannot_escape(self):
        outside = self.home / 'outside'
        outside.mkdir()
        (self.live / 'hypr').symlink_to(outside)
        result = self.run_action('install', '--yes')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(list(outside.iterdir()), [])

    def test_internal_source_symlink_survives_repeat_install(self):
        self.write(self.repo / 'config/quickshell/ii/icon.svg', '<svg/>')
        (self.repo / 'config/quickshell/ii/alias.svg').symlink_to('icon.svg')
        self.require_ok(self.run_action('install', '--yes'))
        self.require_ok(self.run_action('install', '--yes'))
        self.assertEqual((self.live / 'quickshell/ii/alias.svg').readlink(), Path('icon.svg'))

    def test_lock_refuses_parallel_install_without_config_writes(self):
        lock = self.state / 'hyprland-dots/operation.lock'
        lock.mkdir(parents=True)
        result = self.run_action('install', '--yes')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(list(self.live.iterdir()), [])

    def test_missing_marker_fails_before_backup(self):
        (self.repo / 'config/hypr/hyprland.lua').unlink()
        self.assertNotEqual(self.run_action('install', '--yes').returncode, 0)
        self.assertFalse(self.state.exists())

    def test_binary_assets_are_not_rewritten(self):
        data = b'\xff@HOME@\x00'
        self.assertEqual(dotsctl.render(data, self.home, self.live), data)

    def test_wrapper_dry_run_is_offline_and_does_not_write(self):
        result = subprocess.run(['bash', str(ROOT / 'install.sh'), '--dry-run'],
                                env=self.env, text=True, capture_output=True)
        self.require_ok(result)
        self.assertFalse(self.state.exists())
        self.assertEqual(list(self.live.iterdir()), [])


if __name__ == '__main__':
    unittest.main()
