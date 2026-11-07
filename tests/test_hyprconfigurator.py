"""Tests for scripts/hyprland/hyprconfigurator.py (temp dirs only).

FIXTURE_GENERATOR: tests/fixtures/hyprland-options.json comes from the
read-only `hyprctl -j descriptions` of a running Hyprland session:

    hyprctl -j descriptions | python -c '
    import json, sys
    d = json.load(sys.stdin)
    t = lambda v: {bool: "bool", int: "int", float: "float", str: "string", list: "list"}[type(v)]
    out = {"_comment": "...", "options": [
        {"name": x["name"], "type": t(x["default"]), "default": x["default"],
         "min": x.get("min"), "max": x.get("max"), "map": x.get("map")}
        for x in sorted(d, key=lambda x: x["name"])]}
    json.dump(out, open("tests/fixtures/hyprland-options.json", "w"), indent=1, sort_keys=True)'

`current` is dropped because it is machine state.
"""
from __future__ import annotations

import importlib.util
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "config/quickshell/ii/scripts/hyprland/hyprconfigurator.py"
FIXTURE = ROOT / "tests/fixtures/hyprland-options.json"
spec = importlib.util.spec_from_file_location("hyprconfigurator", SCRIPT)
assert spec is not None and spec.loader is not None
hc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(hc)


class HyprconfiguratorTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.dir = Path(temp.name)
        self.file = self.dir / "sub/main.lua"

    def run_cli(self, *args, check=True):
        proc = subprocess.run(
            [sys.executable, str(SCRIPT), "--file", str(self.file), *args],
            capture_output=True, text=True,
        )
        if check:
            self.assertEqual(proc.returncode, 0, proc.stderr)
        return proc

    def text(self):
        return self.file.read_text()

    def listed(self):
        return json.loads(self.run_cli("--list", "--json").stdout)

    def test_legacy_set_format_unchanged_for_numbers_and_bools(self):
        self.run_cli("--set", "general:gaps_in", "0", "--set", "animations:enabled", "true")
        self.assertEqual(
            self.text(),
            "hl.config({general={gaps_in=0}})\nhl.config({animations={enabled=true}})\n",
        )

    def test_legacy_set_infers_string(self):
        self.run_cli("--set", "decoration:screen_shader", "/tmp/a b.frag")
        self.assertEqual(self.text(), 'hl.config({decoration={screen_shader="/tmp/a b.frag"}})\n')

    def test_escapes_quotes_and_backslashes(self):
        value = 'a"b\\c\\"d'
        self.run_cli("--set-typed", "input:kb_layout", "string", value)
        self.assertEqual(self.text(), 'hl.config({input={kb_layout="a\\"b\\\\c\\\\\\"d"}})\n')
        self.assertEqual(self.listed(), {"input:kb_layout": value})

    def test_rejects_control_characters(self):
        # NUL cannot travel through argv; it is covered in-process below.
        self.assertEqual(hc.main(["--file", str(self.file), "--set", "a:b", "a\x00b"]), 1)
        for value in ("a\nb", "a\rb", "a\tb", "a\x7fb", "a\x85b"):
            for args in (("--set", "input:kb_layout", value),
                         ("--set-typed", "input:kb_layout", "string", value)):
                proc = self.run_cli(*args, check=False)
                self.assertNotEqual(proc.returncode, 0, repr(value))
                self.assertIn("control character", proc.stderr)
        self.assertFalse(self.file.exists())

    def test_rejects_invalid_identifiers(self):
        for key in ("input:touchpad:tap-to-click", "a::b", "", "1a", "a.b", "general:end",
                    "a b", "x}}),os.exit(", "a\n"):
            proc = self.run_cli("--set", key, "1", check=False)
            self.assertEqual(proc.returncode, 1, key)
            self.assertIn("not a Lua identifier", proc.stderr)
            proc = self.run_cli("--reset", key, check=False)
            self.assertEqual(proc.returncode, 1, key)
        self.assertFalse(self.file.exists())

    def test_typed_formatting(self):
        self.run_cli(
            "--set-typed", "a:b", "bool", "false",
            "--set-typed", "a:i", "int", "-42",
            "--set-typed", "a:f", "float", "0.5",
            "--set-typed", "a:g", "float", "2",
            "--set-typed", "a:s", "string", "1",
            "--set-typed", "a:e", "string", "",
        )
        self.assertEqual(self.text(), (
            "hl.config({a={b=false}})\nhl.config({a={i=-42}})\nhl.config({a={f=0.5}})\n"
            'hl.config({a={g=2.0}})\nhl.config({a={s="1"}})\nhl.config({a={e=""}})\n'
        ))
        self.assertEqual(self.listed(), {"a:b": False, "a:i": -42, "a:f": 0.5, "a:g": 2.0,
                                         "a:s": "1", "a:e": ""})

    def test_typed_validation_is_strict(self):
        bad = [("bool", "1"), ("bool", "True"), ("int", "1.0"), ("int", " 1"), ("int", "0x10"),
               ("int", str(2**63)), ("float", "inf"), ("float", "nan"), ("float", "1_0"),
               ("float", ""), ("color", "x")]
        for type_name, value in bad:
            proc = self.run_cli("--set-typed", "a:b", type_name, value, check=False)
            self.assertEqual(proc.returncode, 1, (type_name, value))
            self.assertIn("hyprconfigurator: error:", proc.stderr)
        self.assertFalse(self.file.exists())

    def test_idempotent_and_no_rewrite_when_unchanged(self):
        args = ("--set", "general:gaps_in", "4", "--set-typed", "input:kb_variant", "string", "")
        self.run_cli(*args)
        first = self.text()
        mtime = self.file.stat().st_mtime_ns
        os.utime(self.file, ns=(mtime - 10**9, mtime - 10**9))
        self.run_cli(*args)
        self.assertEqual(self.text(), first)
        self.assertEqual(self.file.stat().st_mtime_ns, mtime - 10**9)

    def test_set_replaces_in_place_and_reset_removes(self):
        self.file.parent.mkdir(parents=True)
        self.file.write_text(
            "-- keep me\n"
            "hl.config({general={gaps_in=0}})\n"
            "hl.config({general={gaps_out=0}})\n"
            "hl.config({general={gaps_in=9}})\n"
            "hl.config({decoration={screen_shader=\"/old/path\"}})\n"
            "hl.config({general={gaps_in=1, gaps_out=2}})\n"
        )
        self.run_cli("--set", "general:gaps_in", "5", "--reset", "decoration:screen_shader")
        self.assertEqual(self.text(), (
            "-- keep me\n"
            "hl.config({general={gaps_in=5}})\n"
            "hl.config({general={gaps_out=0}})\n"
            "hl.config({general={gaps_in=1, gaps_out=2}})\n"
        ))
        self.run_cli("--unset", "general:gaps_out", "--set", "general:gaps_in", "[[EMPTY]]")
        self.assertEqual(self.text(), "-- keep me\nhl.config({general={gaps_in=1, gaps_out=2}})\n")

    def test_reads_legacy_unescaped_string_and_overwrites_it(self):
        self.file.parent.mkdir(parents=True)
        self.file.write_text('hl.config({decoration={screen_shader="a"b"}})\n')
        proc = self.run_cli("--list", "--json")
        self.assertEqual(json.loads(proc.stdout), {})
        self.assertIn("unparsable", proc.stderr)
        self.run_cli("--set", "decoration:screen_shader", 'a"b')
        self.assertEqual(self.text(), 'hl.config({decoration={screen_shader="a\\"b"}})\n')

    def test_list_json_round_trip(self):
        values = {"general:gaps_in": 3, "decoration:active_opacity": 0.85,
                  "input:touchpad:tap_to_click": True, "input:kb_layout": 'us,"es"\\x',
                  "misc:vrr": 0}
        types = {int: "int", float: "float", bool: "bool", str: "string"}
        args = []
        for key, value in values.items():
            raw = json.dumps(value) if not isinstance(value, str) else value
            args += ["--set-typed", key, types[type(value)], raw]
        self.run_cli(*args)
        listed = self.listed()
        self.assertEqual(listed, values)
        self.assertIsInstance(listed["decoration:active_opacity"], float)
        self.assertIsInstance(listed["input:touchpad:tap_to_click"], bool)

    def test_list_missing_file_and_requires_json(self):
        self.assertEqual(self.listed(), {})
        self.assertEqual(self.run_cli("--list", check=False).returncode, 1)
        self.assertEqual(self.run_cli("--list", "--json", "--reset", "a", check=False).returncode, 1)

    def test_header_written_once(self):
        self.run_cli("--header", "Managed by the settings app.\nDo not edit.", "--set", "a:b", "1")
        self.run_cli("--header", "Managed by the settings app.\nDo not edit.", "--set", "a:c", "2")
        self.assertEqual(self.text(), (
            "-- Managed by the settings app.\n-- Do not edit.\n"
            "hl.config({a={b=1}})\nhl.config({a={c=2}})\n"
        ))
        self.assertEqual(self.listed(), {"a:b": 1, "a:c": 2})

    def test_header_rejects_control_chars(self):
        proc = self.run_cli("--header", "x\x1by", "--set", "a:b", "1", check=False)
        self.assertEqual(proc.returncode, 1)
        self.assertFalse(self.file.exists())

    def test_atomic_write_keeps_mode_and_leaves_no_temp(self):
        self.file.parent.mkdir(parents=True)
        self.file.write_text("")
        os.chmod(self.file, 0o600)
        self.run_cli("--set", "a:b", "1")
        self.assertEqual(stat.S_IMODE(self.file.stat().st_mode), 0o600)
        self.assertEqual(sorted(p.name for p in self.file.parent.iterdir()), ["main.lua"])

    def test_new_file_mode(self):
        self.run_cli("--set", "a:b", "1")
        self.assertEqual(stat.S_IMODE(self.file.stat().st_mode), 0o644)

    def test_failed_write_keeps_original(self):
        self.file.parent.mkdir(parents=True)
        self.file.write_text("hl.config({a={b=1}})\n")
        os.chmod(self.file.parent, 0o500)
        self.addCleanup(os.chmod, self.file.parent, 0o700)
        if os.access(self.file.parent, os.W_OK):
            self.skipTest("running with privileges that ignore directory permissions")
        proc = self.run_cli("--set", "a:b", "2", check=False)
        self.assertEqual(proc.returncode, 1)
        self.assertIn("cannot write", proc.stderr)
        self.assertEqual(self.text(), "hl.config({a={b=1}})\n")

    def test_no_arguments_is_an_error(self):
        proc = self.run_cli(check=False)
        self.assertEqual(proc.returncode, 1)
        self.assertIn("at least one key", proc.stderr)

    def test_generated_lua_is_valid(self):
        lua = shutil.which("lua") or shutil.which("luac")
        if not lua:
            self.skipTest("no luac/lua binary available")
        self.run_cli(
            "--header", "header",
            "--set", "general:gaps_in", "4",
            "--set-typed", "decoration:active_opacity", "float", "0.9",
            "--set-typed", "input:touchpad:tap_to_click", "bool", "true",
            "--set-typed", "input:kb_layout", "string", 'us"\\]]--',
        )
        if os.path.basename(lua).startswith("luac"):
            proc = subprocess.run([lua, "-p", str(self.file)], capture_output=True, text=True)
            self.assertEqual(proc.returncode, 0, proc.stderr)
            return
        # Execute against a stub `hl` and check the values Lua actually sees.
        stub = self.dir / "check.lua"
        stub.write_text(
            "local seen = {}\n"
            "local function walk(t, prefix)\n"
            "  for k, v in pairs(t) do\n"
            "    local key = prefix and (prefix .. ':' .. k) or k\n"
            "    if type(v) == 'table' then walk(v, key) else seen[key] = v end\n"
            "  end\n"
            "end\n"
            "hl = { config = function(t) walk(t, nil) end }\n"
            f"dofile({json.dumps(str(self.file))})\n"
            "assert(seen['input:kb_layout'] == 'us\"\\\\]]--')\n"
            "assert(seen['general:gaps_in'] == 4)\n"
            "assert(seen['input:touchpad:tap_to_click'] == true)\n"
        )
        proc = subprocess.run([lua, str(stub)], capture_output=True, text=True)
        self.assertEqual(proc.returncode, 0, proc.stderr)

    def test_parse_line_matches_config_line(self):
        for key, value in (("a:b:c", True), ("x", -3), ("y:z", 1e-05), ("s:t", 'q"\\')):
            line = hc.config_line(key.split(":"), value)
            self.assertEqual(hc.parse_line(line), (key, value))


class FixtureTests(unittest.TestCase):
    def test_fixture_shape(self):
        data = json.loads(FIXTURE.read_text())
        self.assertIn("_comment", data)
        options = data["options"]
        self.assertGreater(len(options), 300)
        names = [o["name"] for o in options]
        self.assertEqual(len(names), len(set(names)))
        for option in options:
            self.assertEqual(set(option), {"name", "type", "default", "min", "max", "map"})
            self.assertNotIn("current", option)
            self.assertIn(option["type"], {"bool", "int", "float", "string", "list"})
        by_name = {o["name"]: o for o in options}
        self.assertEqual(by_name["input:touchpad:tap-to-click"]["type"], "bool")


if __name__ == "__main__":
    unittest.main()
