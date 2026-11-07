from __future__ import annotations

import importlib.util
import io
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / 'scripts/settings/monitorsgen.py'
spec = importlib.util.spec_from_file_location('monitorsgen', SCRIPT)
monitorsgen = importlib.util.module_from_spec(spec)
spec.loader.exec_module(monitorsgen)
LUAC = shutil.which('luac') or shutil.which('luac5.4')


def run(spec_value: object, *args: str, raw: str | None = None) -> subprocess.CompletedProcess:
    data = raw if raw is not None else json.dumps(spec_value)
    return subprocess.run([sys.executable, str(SCRIPT), *args], input=data, capture_output=True, text=True,
                          timeout=30)


def one(**fields) -> dict:
    return {'monitors': [{'name': 'eDP-1', **fields}]}


def table(**fields) -> str:
    return monitorsgen.lua_table(monitorsgen.parse_spec(one(**fields))[0])


class MonitorsgenFieldTests(unittest.TestCase):
    def test_defaults(self) -> None:
        self.assertEqual(table(), '{ output = "eDP-1", mode = "preferred", position = "auto", scale = 1, '
                                  'transform = 0, disabled = false, vrr = 0 }')

    def test_each_field(self) -> None:
        cases = {
            'enabled': ({'enabled': False}, 'disabled = true'),
            'mode': ({'mode': '1920x1080@144.00Hz'}, 'mode = "1920x1080@144.00Hz"'),
            'mode-no-suffix': ({'mode': '2560x1440@60'}, 'mode = "2560x1440@60"'),
            'position': ({'position': {'x': -1920, 'y': 0}}, 'position = "-1920x0"'),
            'scale': ({'scale': 1.25}, 'scale = 1.25'),
            'scale-int-float': ({'scale': 2.0}, 'scale = 2'),
            'transform': ({'transform': 7}, 'transform = 7'),
            'mirror': ({'mirror': 'HDMI-A-1'}, 'mirror = "HDMI-A-1"'),
            'vrr-int': ({'vrr': 2}, 'vrr = 2'),
            'vrr-bool': ({'vrr': True}, 'vrr = 1'),
            'bitdepth': ({'bitdepth': 10}, 'bitdepth = 10'),
            'quoting': ({'name': 'desc:Some "Vendor" \\ 1'}, 'output = "desc:Some \\"Vendor\\" \\\\ 1"'),
        }
        for label, (fields, expected) in cases.items():
            with self.subTest(label):
                monitor = {'name': 'eDP-1', **fields}
                # A companion output keeps the layout valid when this one is disabled.
                parsed = monitorsgen.parse_spec({'monitors': [monitor, {'name': 'Z-1'}]})
                rule = next(m for m in parsed if m['name'] == monitor['name'])
                self.assertIn(expected, monitorsgen.lua_table(rule))

    def test_invalid_fields(self) -> None:
        cases = [
            one(enabled=1), one(mode='1920x1080'), one(mode='0x1080@60'), one(mode='1920x1080@60Hz '),
            one(mode=60), one(position='0x0'), one(position={'x': 0}), one(position={'x': 1.5, 'y': 0}),
            one(position={'x': 70000, 'y': 0}), one(scale=0.1), one(scale=11), one(scale='1'), one(scale=True),
            one(scale=float('nan')), one(transform=8), one(transform=-1), one(transform=True), one(vrr=3),
            one(vrr='on'), one(bitdepth=12), one(bitdepth=True), one(mirror='eDP-1'), one(mirror=''),
            one(extra=1), {'monitors': [{'enabled': True}]}, {'monitors': [{'name': ''}]},
            {'monitors': [{'name': 'x' * 129}]}, {'monitors': []}, {'monitors': {}}, [], {'monitors': [], 'x': 1},
            {'monitors': [{'name': 'a'}, {'name': 'a'}]},
            {'monitors': [{'name': 'a', 'enabled': False}]},
        ]
        for value in cases:
            with self.subTest(value=repr(value)[:80]), self.assertRaises(monitorsgen.SpecError):
                monitorsgen.parse_spec(value)

    def test_rejects_control_characters(self) -> None:
        for bad in ('eDP-1\n', 'eDP\x00', 'eDP\x1b[31m', 'eDP\x7f', 'eDP '):
            with self.subTest(bad=repr(bad)), self.assertRaisesRegex(monitorsgen.SpecError, 'control'):
                monitorsgen.parse_spec({'monitors': [{'name': bad}]})
            with self.subTest(mirror=repr(bad)), self.assertRaisesRegex(monitorsgen.SpecError, 'control'):
                monitorsgen.parse_spec(one(mirror=bad))


class MonitorsgenOutputTests(unittest.TestCase):
    SPEC = {'monitors': [
        {'name': 'eDP-1', 'enabled': False},
        {'name': 'HDMI-A-1', 'mode': '1920x1080@60.00Hz', 'position': {'x': 0, 'y': 0}, 'scale': 1},
        {'name': 'DP-2', 'mirror': 'HDMI-A-1'},
    ]}

    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.target = Path(self.temp.name) / 'hypr/monitors.lua'

    def test_enabled_first_stable_order(self) -> None:
        names = [monitor['name'] for monitor in monitorsgen.parse_spec(self.SPEC)]
        self.assertEqual(names, ['HDMI-A-1', 'DP-2', 'eDP-1'])

    def test_lua_expr_equals_file_rules(self) -> None:
        printed = run(self.SPEC, '--print')
        expr = run(self.SPEC, '--lua-expr')
        self.assertEqual(printed.returncode, 0, printed.stderr)
        self.assertEqual(expr.returncode, 0, expr.stderr)
        rules = [line for line in printed.stdout.splitlines() if line.startswith('hl.monitor(')]
        self.assertEqual(len(rules), 3)
        self.assertEqual(expr.stdout, '; '.join(rules) + '\n')
        single = run(self.SPEC, '--lua-expr', '--name', 'DP-2')
        self.assertEqual(single.stdout.strip(), rules[1])
        self.assertEqual(run(self.SPEC, '--lua-expr', '--name', 'nope').returncode, 2)
        self.assertEqual(run(self.SPEC, '--name', 'DP-2').returncode, 2)

    @unittest.skipUnless(LUAC, 'luac is not installed')
    def test_generated_lua_parses(self) -> None:
        source = Path(self.temp.name) / 'check.lua'
        source.write_text(monitorsgen.render_file(monitorsgen.parse_spec(self.SPEC)))
        result = subprocess.run([LUAC, '-p', str(source)], capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_write_is_atomic_deterministic_and_marked(self) -> None:
        result = run(self.SPEC, '--output', str(self.target))
        self.assertEqual(result.returncode, 0, result.stderr)
        content = self.target.read_text()
        self.assertTrue(content.startswith(monitorsgen.MARKER + '\n'))
        self.assertEqual(content, run(self.SPEC, '--print').stdout)
        self.assertEqual(run(self.SPEC, '--output', str(self.target)).returncode, 0)
        self.assertEqual(self.target.read_text(), content)
        self.assertEqual([p.name for p in self.target.parent.iterdir()], ['monitors.lua'])

    def test_invalid_input_exit_code_and_no_write(self) -> None:
        self.assertEqual(run(None, '--output', str(self.target), raw='{').returncode, 2)
        result = run(one(transform=9), '--output', str(self.target))
        self.assertEqual(result.returncode, 2)
        self.assertIn('transform', result.stderr)
        self.assertFalse(self.target.exists())

    def test_unmanaged_target_refused_then_backed_up_with_force(self) -> None:
        self.target.parent.mkdir(parents=True)
        self.target.write_text('hl.monitor({ output = "", mode = "preferred" })\n')
        refused = run(self.SPEC, '--output', str(self.target))
        self.assertEqual(refused.returncode, 3)
        self.assertIn('--force', refused.stderr)
        self.assertNotIn(monitorsgen.MARKER, self.target.read_text())
        forced = run(self.SPEC, '--output', str(self.target), '--force')
        self.assertEqual(forced.returncode, 0, forced.stderr)
        backups = sorted(self.target.parent.glob('monitors.lua.bak-*'))
        self.assertEqual(len(backups), 1)
        self.assertEqual(backups[0].read_text(), 'hl.monitor({ output = "", mode = "preferred" })\n')
        self.assertTrue(self.target.read_text().startswith(monitorsgen.MARKER))
        # A managed file is replaced without a new backup.
        self.assertEqual(run(self.SPEC, '--output', str(self.target), '--force').returncode, 0)
        self.assertEqual(len(list(self.target.parent.glob('monitors.lua.bak-*'))), 1)

    def test_backup_name_collision_gets_counter(self) -> None:
        self.target.parent.mkdir(parents=True)
        self.target.write_text('a\n')
        first = monitorsgen.backup(self.target)
        second = monitorsgen.backup(self.target)
        self.assertNotEqual(first, second)
        self.assertTrue(first.exists() and second.exists())

    def test_refuses_symlink_target(self) -> None:
        real = Path(self.temp.name) / 'real.lua'
        real.write_text(monitorsgen.MARKER + '\n')
        self.target.parent.mkdir(parents=True)
        os.symlink(real, self.target)
        self.assertEqual(run(self.SPEC, '--output', str(self.target), '--force').returncode, 3)
        self.assertTrue(self.target.is_symlink())


if __name__ == '__main__':
    unittest.main()
