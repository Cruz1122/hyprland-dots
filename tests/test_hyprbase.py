"""hyprbase.py: the dotfiles' Hyprland base values, read by running hyprland.lua sandboxed."""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "config/quickshell/ii/scripts/settings/hyprbase.py"
OPTIONS = ROOT / "tests/fixtures/hyprland-options.json"
SAMPLE = ROOT / "tests/fixtures/hyprbase-sample.json"

CURVES = {
    "expressiveFastSpatial": [0.42, 1.67, 0.21, 0.90],
    "expressiveSlowSpatial": [0.39, 1.29, 0.35, 0.98],
    "expressiveDefaultSpatial": [0.38, 1.21, 0.22, 1.00],
    "emphasizedDecel": [0.05, 0.7, 0.1, 1],
    "emphasizedAccel": [0.3, 0, 0.8, 0.15],
    "standardDecel": [0, 0, 0, 1],
    "menu_decel": [0.1, 1, 0, 1],
    "menu_accel": [0.52, 0.03, 0.72, 0.08],
    "stall": [1, -0.1, 0.7, 0.85],
}
# (speed, bezier, style) of every hl.animation in config/hypr/hyprland/general.lua.
ANIMATIONS = {
    "windowsIn": (3, "emphasizedDecel", "popin 80%"),
    "fadeIn": (3, "emphasizedDecel", None),
    "windowsOut": (2, "emphasizedDecel", "popin 90%"),
    "fadeOut": (2, "emphasizedDecel", None),
    "windowsMove": (3, "emphasizedDecel", "slide"),
    "border": (10, "emphasizedDecel", None),
    "layersIn": (2.7, "emphasizedDecel", "popin 93%"),
    "layersOut": (2.4, "menu_accel", "popin 94%"),
    "fadeLayersIn": (0.5, "menu_decel", None),
    "fadeLayersOut": (2.7, "stall", None),
    "workspaces": (7, "menu_decel", "slide"),
    "specialWorkspaceIn": (2.8, "emphasizedDecel", "slidevert"),
    "specialWorkspaceOut": (1.2, "emphasizedAccel", "slidevert"),
    "zoomFactor": (3, "standardDecel", None),
}
ANIMATION_FIELDS = {"enabled", "speed", "bezier", "spring", "style"}


def run(config_dir: Path, *extra: str, env: dict | None = None) -> tuple[int, dict, str]:
    proc = subprocess.run(
        [sys.executable, str(SCRIPT), "--json", "--config-dir", str(config_dir), *extra],
        capture_output=True, text=True, timeout=30, env=env,
    )
    lines = [line for line in proc.stdout.splitlines() if line.strip()]
    if len(lines) != 1:
        raise AssertionError(f"expected one JSON line, got {proc.stdout!r} / {proc.stderr!r}")
    return proc.returncode, json.loads(lines[0]), proc.stderr


def check_schema(test: unittest.TestCase, data: dict) -> None:
    """The shape of contracts §2, shared by the real output and the A1 sample fixture."""
    test.assertEqual(set(data) - {"_comment"}, {"ok", "errors", "config", "curves", "animations"})
    test.assertIsInstance(data["ok"], bool)
    test.assertIsInstance(data["errors"], list)
    test.assertTrue(all(isinstance(e, str) for e in data["errors"]))
    for name, value in data["config"].items():
        test.assertRegex(name, r"^[a-z_0-9]+(:[a-z_0-9]+)*(:col\.[a-z_0-9]+|\.[a-z_0-9]+)?$")
        if isinstance(value, list):
            test.assertTrue(all(isinstance(v, (bool, int, float, str)) for v in value), name)
        else:
            test.assertIsInstance(value, (bool, int, float, str), name)
    for name, curve in data["curves"].items():
        test.assertIn(curve.get("type"), ("bezier", "spring"), name)
        if curve["type"] == "bezier":
            test.assertEqual(len(curve["points"]), 4, name)
            test.assertTrue(all(isinstance(p, (int, float)) for p in curve["points"]), name)
        else:
            for field in ("mass", "stiffness", "damping"):
                test.assertIsInstance(curve.get(field), (int, float), (name, field))
    for leaf, anim in data["animations"].items():
        test.assertLessEqual(set(anim), ANIMATION_FIELDS, leaf)
        test.assertFalse("bezier" in anim and "spring" in anim, leaf)
        if "enabled" in anim:
            test.assertIsInstance(anim["enabled"], bool, leaf)
        if "speed" in anim:
            test.assertIsInstance(anim["speed"], (int, float), leaf)
        for field in ("bezier", "spring", "style"):
            if field in anim:
                test.assertIsInstance(anim[field], str, (leaf, field))


class HyprbaseTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp(prefix="hyprbase-test-"))
        self.addCleanup(shutil.rmtree, self.tmp, True)
        # Not under .config/hypr: HOME/.config/hypr/... paths must map into it.
        self.dir = self.tmp / "hypr"
        shutil.copytree(ROOT / "config/hypr", self.dir)

    def write(self, rel: str, text: str) -> Path:
        path = self.dir / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
        return path

    def test_repository_base_values(self) -> None:
        code, data, _ = run(self.dir, "--options", str(OPTIONS))
        self.assertEqual(code, 0, data)
        self.assertTrue(data["ok"])
        self.assertEqual(data["errors"], [], "every recorded name is a known getoption name")
        config = data["config"]
        self.assertEqual(config["general:gaps_in"], 4)
        self.assertEqual(config["general:gaps_out"], 5)
        self.assertIs(config["decoration:blur:enabled"], True)
        self.assertIs(config["decoration:shadow:enabled"], True)
        self.assertIs(config["animations:enabled"], True)
        self.assertEqual(config["decoration:rounding"], 18)
        self.assertEqual(config["decoration:shadow:offset"], [0, 2])
        self.assertIs(config["misc:animate_manual_resizes"], False)
        # colors.lua comes after general.lua and wins, as in Hyprland.
        self.assertEqual(config["general:col.active_border"], "rgba(47474777)")
        self.assertEqual(set(data["curves"]), set(CURVES))
        for name, points in CURVES.items():
            self.assertEqual(data["curves"][name], {"type": "bezier", "points": points}, name)
        self.assertEqual(set(data["animations"]), set(ANIMATIONS))
        for leaf, (speed, bezier, style) in ANIMATIONS.items():
            expected = {"enabled": True, "speed": speed, "bezier": bezier}
            if style is not None:
                expected["style"] = style
            self.assertEqual(data["animations"][leaf], expected, leaf)
        check_schema(self, data)

    def test_app_and_game_mode_files_are_not_part_of_the_base(self) -> None:
        # The A0 hyprland.lua does not require shell-animations yet; make sure it would be skipped.
        entry = self.dir / "hyprland.lua"
        entry.write_text(entry.read_text(encoding="utf-8").replace(
            'require("hyprland.shellOverrides.main")',
            'pcall(require, "custom.shell-animations")\nrequire("hyprland.shellOverrides.main")'), encoding="utf-8")
        self.write("custom/shell-settings.lua", "hl.config({general={gaps_in=33}})\n")
        self.write("custom/shell-animations.lua",
                   'hl.animation({leaf="windowsIn", enabled=true, speed=9, bezier="default"})\n')
        self.write("hyprland/shellOverrides/main.lua",
                   "hl.config({animations={enabled=0}})\nhl.config({general={gaps_in=0}})\n")
        self.write("custom/general.lua",
                   "hl.config({general={gaps_out=11}})\n"
                   'hl.curve("ii_mine", {type="spring", mass=1, stiffness=260, damping=18})\n'
                   'hl.animation({leaf="fadeDpms", enabled=false})\n'
                   'hl.animation({leaf="workspaces", enabled=true, speed=4, spring="ii_mine", style="fade"})\n')
        code, data, _ = run(self.dir)
        self.assertEqual(code, 0, data)
        config = data["config"]
        self.assertEqual(config["general:gaps_in"], 4)
        self.assertIs(config["animations:enabled"], True)
        self.assertEqual(data["animations"]["windowsIn"]["speed"], 3)
        # custom/* loads before the app's files and is part of the base.
        self.assertEqual(config["general:gaps_out"], 11)
        self.assertEqual(data["curves"]["ii_mine"], {"type": "spring", "mass": 1, "stiffness": 260, "damping": 18})
        self.assertEqual(data["animations"]["fadeDpms"], {"enabled": False})
        self.assertEqual(data["animations"]["workspaces"],
                         {"enabled": True, "speed": 4, "spring": "ii_mine", "style": "fade"})
        check_schema(self, data)

    def test_identity_layout_under_dot_config(self) -> None:
        home = self.tmp / "home"
        (home / ".config").mkdir(parents=True)
        shutil.move(str(self.dir), str(home / ".config/hypr"))
        self.dir = home / ".config/hypr"
        self.write("custom/general.lua", "hl.config({general={gaps_out=12}})\n")
        code, data, _ = run(self.dir)
        self.assertEqual(code, 0, data)
        self.assertEqual(data["config"]["general:gaps_out"], 12)

    def test_syntax_error_fails_with_one_json_object(self) -> None:
        self.write("custom/general.lua", "hl.config({general={gaps_out=}})\n")
        code, data, _ = run(self.dir)
        self.assertEqual(code, 1)
        self.assertFalse(data["ok"])
        self.assertTrue(any("general.lua" in e for e in data["errors"]), data["errors"])
        self.assertEqual(data["config"], {})
        check_schema(self, data)

    def test_missing_entry_point_fails(self) -> None:
        (self.dir / "hyprland.lua").unlink()
        code, data, _ = run(self.dir)
        self.assertEqual(code, 1)
        self.assertFalse(data["ok"])

    def test_infinite_loop_is_killed(self) -> None:
        self.write("custom/general.lua", "while true do end\n")
        started = time.monotonic()
        code, data, _ = run(self.dir)
        self.assertLess(time.monotonic() - started, 15)
        self.assertEqual(code, 1)
        self.assertFalse(data["ok"])

    def test_missing_module_is_noted_not_fatal(self) -> None:
        shutil.rmtree(self.dir / "hyprland/services")
        code, data, _ = run(self.dir)
        self.assertEqual(code, 0, data)
        self.assertTrue(any("hyprland.services" in e for e in data["errors"]), data["errors"])
        self.assertEqual(data["config"]["general:gaps_in"], 4)

    def test_unknown_option_names_are_reported(self) -> None:
        self.write("custom/general.lua", "hl.config({general={not_an_option=1}})\n")
        code, data, _ = run(self.dir, "--options", str(OPTIONS))
        self.assertEqual(code, 0, data)
        self.assertIn("unknown option 'general:not_an_option'", data["errors"])

    def test_io_and_os_escapes_are_blocked(self) -> None:
        outside = self.tmp / "outside"
        outside.mkdir()
        victim = self.dir / "victim.txt"
        victim.write_text("keep", encoding="utf-8")
        secret = outside / "secret.txt"
        secret.write_text("secret", encoding="utf-8")
        lua = f"""
local outside, dir = {json.dumps(str(outside))}, {json.dumps(str(self.dir))}
local w1 = io.open(outside .. "/w1.txt", "w")
local w2 = io.open(dir .. "/w2.txt", "a")
local r1 = io.open(outside .. "/secret.txt", "r")
local r2 = io.open(dir .. "/../outside/secret.txt", "r")
local r3 = io.open(dir .. "/victim.txt", "r")
local read = r3 and r3:read("a") or ""
if r3 then r3:close() end
os.execute("touch " .. outside .. "/exec.txt")
local p = io.popen and io.popen("touch " .. outside .. "/popen.txt")
os.remove(dir .. "/victim.txt")
os.rename(dir .. "/victim.txt", outside .. "/moved.txt")
local l1 = load("return 1")
local l2 = loadfile(outside .. "/secret.txt")
local ok_dofile = pcall(dofile, outside .. "/secret.txt")
io.write("leak")
os.exit(3)
hl.config({{ misc = {{ swallow_regex = table.concat({{
  tostring(w1 == nil), tostring(w2 == nil), tostring(r1 == nil), tostring(r2 == nil),
  read, tostring(p == nil), tostring(l1 == nil), tostring(l2 == nil), tostring(os.getenv("PATH"))
}}, ",") }} }})
"""
        self.write("custom/general.lua", lua)
        env = dict(os.environ, LUA_INIT=f'os.execute("touch {outside}/init.txt")')
        code, data, _ = run(self.dir, env=env)
        self.assertEqual(code, 0, data)
        self.assertEqual(data["config"]["misc:swallow_regex"], "true,true,true,true,keep,true,true,true,nil")
        self.assertEqual(sorted(p.name for p in outside.iterdir()), ["secret.txt"])
        self.assertTrue(victim.exists())
        self.assertFalse((self.dir / "w2.txt").exists())
        for what in ("os.execute", "os.remove", "os.rename", "load", "loadfile", "io.write", "os.exit"):
            self.assertTrue(any(e.startswith(f"blocked {what}") for e in data["errors"]), (what, data["errors"]))

    def test_string_and_file_metatables_cannot_bypass_the_confinement(self) -> None:
        # A fake string.gmatch could hand confine() a single segment that
        # contains "/../"; the lexical ".." check would never see it.
        outside = self.tmp / "outside"
        outside.mkdir()
        (outside / "secret.txt").write_text("TOPSECRET", encoding="utf-8")
        segments = [*self.dir.parts[1:], "custom/../../outside/secret.txt"]
        lua = f"""
local segs = {{{", ".join(json.dumps(s) for s in segments)}}}
local results = {{}}
local smt = getmetatable("")
local handle = io.open({json.dumps(str(self.dir / "hyprland.lua"))}, "r")
results[#results + 1] = tostring(handle ~= nil)
local fmt = handle and getmetatable(handle)
results[#results + 1] = tostring(smt == nil)
results[#results + 1] = tostring(fmt == nil)
if smt and type(smt.__index) == "table" then
  smt.__index.gmatch = function()
    local i = 0
    return function() i = i + 1; return segs[i] end
  end
end
local f = io.open(os.getenv("HOME") .. "/.config/hypr/EXPLOIT", "r")
results[#results + 1] = f and (f:read("a") or "") or "blocked"
hl.config({{ misc = {{ swallow_regex = table.concat(results, ",") }} }})
"""
        self.write("custom/general.lua", lua)
        code, data, _ = run(self.dir)
        self.assertEqual(code, 0, data)
        self.assertEqual(data["config"]["misc:swallow_regex"], "true,true,true,blocked")
        self.assertNotIn("TOPSECRET", json.dumps(data))

    def test_require_stays_inside_the_config_dir(self) -> None:
        (self.tmp / "evil.lua").write_text("hl.config({general={gaps_in=99}})\n", encoding="utf-8")
        self.write("custom/general.lua", 'require("..evil")\nrequire("/evil")\n')
        code, data, _ = run(self.dir)
        self.assertEqual(code, 0, data)
        self.assertEqual(data["config"]["general:gaps_in"], 4)

    def test_sample_fixture_matches_the_schema(self) -> None:
        self.assertTrue(SAMPLE.is_file(), "tests/fixtures/hyprbase-sample.json is missing")
        sample = json.loads(SAMPLE.read_text(encoding="utf-8"))
        check_schema(self, sample)
        code, data, _ = run(self.dir)
        self.assertEqual(code, 0, data)
        check_schema(self, data)
        # Same option names and value types where both define a value.
        for name, value in sample["config"].items():
            if name in data["config"]:
                self.assertEqual(type(data["config"][name]) is bool, type(value) is bool, name)


if __name__ == "__main__":
    unittest.main()
