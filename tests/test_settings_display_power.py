"""Displays and power pages: generator round trips and registry wiring."""
from __future__ import annotations

import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SHELL = ROOT / "config/quickshell/ii"
SETTINGS = SHELL / "modules/settings"
MONITORSGEN = SHELL / "scripts/settings/monitorsgen.py"
IDLEGEN = SHELL / "scripts/settings/idlegen.py"
FIXTURE = ROOT / "tests/fixtures/hyprctl-monitors-all.json"
NODE = shutil.which("node")

# Evaluates the `.pragma library` files in a vm context; `.import` lines are
# replaced by the already evaluated DisplayRules library.
NODE_LOADER = r"""
const fs = require("fs");
const vm = require("vm");
const [rulesPath, logicPath, fixturePath, managedPath] = process.argv.slice(1);
const strip = text => text.split("\n").filter(l => !/^\s*\.(pragma|import)\b/.test(l)).join("\n");
const rules = vm.createContext({});
vm.runInContext(strip(fs.readFileSync(rulesPath, "utf8")), rules);
const logic = vm.createContext({ DisplayRules: rules, Array, JSON, Math, Number, String });
vm.runInContext(strip(fs.readFileSync(logicPath, "utf8")), logic);
const infos = JSON.parse(fs.readFileSync(fixturePath, "utf8"));
const spec = logic.specFromMonitors(infos);
const out = {
  marker: logic.MONITORS_MARKER,
  spec,
  presets: {},
  arrangement: spec.map(m => logic.arrangement(spec, infos, m.name)),
  moved: logic.applyArrangement(spec, infos, "HDMI-A-1", "below:eDP-1"),
  lastOff: logic.setField(logic.setField(spec, "HDMI-A-1", "enabled", false), "eDP-1", "enabled", false),
  scales: logic.scaleChoices(1920, 1080, 1).map(o => o.value),
};
for (const kind of logic.availablePresets(spec))
  out.presets[kind] = logic.preset(spec, infos, kind);
const managed = fs.readFileSync(managedPath, "utf8");
out.fileVrr = logic.vrrFromManagedText(managed);
out.specWithFile = logic.specFromMonitors(infos, out.fileVrr);
out.unmanagedVrr = logic.vrrFromManagedText(managed.split("\n").slice(1).join("\n"));
process.stdout.write(JSON.stringify(out));
"""


def lua_expr(spec: list) -> subprocess.CompletedProcess:
    return subprocess.run(
        [sys.executable, str(MONITORSGEN), "--lua-expr", "--spec-json", json.dumps({"monitors": spec})],
        capture_output=True, text=True, timeout=30)


def load(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


@unittest.skipUnless(NODE, "node is not installed")
class DisplayLogicRoundTripTests(unittest.TestCase):
    # A managed monitors.lua as monitorsgen.py writes it: HDMI-A-1 without vrr
    # (follows misc:vrr), DP-2 fullscreen-only, a quoted name.
    MANAGED_SPEC = [{"name": "eDP-1", "vrr": 0}, {"name": "HDMI-A-1"},
                    {"name": "DP-2", "vrr": 2, "enabled": False}, {"name": 'desc:A "B" \\ C', "vrr": 1}]

    @classmethod
    def setUpClass(cls) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            managed = Path(tmp) / "monitors.lua"
            printed = subprocess.run(
                [sys.executable, str(MONITORSGEN), "--print", "--spec-json", json.dumps({"monitors": cls.MANAGED_SPEC})],
                capture_output=True, text=True, timeout=30)
            if printed.returncode != 0:
                raise AssertionError(printed.stderr)
            managed.write_text(printed.stdout, encoding="utf-8")
            result = subprocess.run(
                [NODE, "-e", NODE_LOADER, str(SHELL / "modules/common/functions/DisplayRules.js"),
                 str(SETTINGS / "backends/DisplayLogic.js"), str(FIXTURE), str(managed)],
                capture_output=True, text=True, timeout=30)
        if result.returncode != 0:
            raise AssertionError(result.stderr)
        cls.out = json.loads(result.stdout)

    def test_marker_matches_generator(self) -> None:
        source = MONITORSGEN.read_text(encoding="utf-8")
        self.assertIn(f"MARKER = '{self.out['marker']}'", source)

    def test_live_spec_is_accepted_by_monitorsgen(self) -> None:
        spec = self.out["spec"]
        self.assertEqual([m["name"] for m in spec], ["eDP-1", "HDMI-A-1", "DP-2"])
        laptop, hdmi, dp = spec
        self.assertEqual(laptop["mode"], "1920x1080@144.00Hz")
        self.assertEqual(laptop["position"], {"x": 0, "y": 0})
        self.assertEqual(hdmi["position"], {"x": 1920, "y": 0})
        self.assertFalse(dp["enabled"])
        self.assertEqual(dp["position"], "auto")
        self.assertEqual(dp["bitdepth"], 10)
        # hyprctl's `vrr` says whether VRR is active now, not the mode: without
        # a managed monitors.lua every output follows misc:vrr.
        self.assertEqual([m["vrr"] for m in spec], [None, None, None])
        self.assertNotIn("vrr =", lua_expr(spec).stdout)
        result = lua_expr(spec)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('hl.monitor({ output = "HDMI-A-1", mode = "1920x1080@60.00Hz", position = "1920x0"', result.stdout)

    # Regression: the spec took vrr from hyprctl's "active now" flag, so
    # keeping any display change wrote vrr = 0 into monitors.lua, which
    # overrides misc:vrr (fullscreen-only VRR reads as off outside fullscreen).
    def test_per_output_vrr_comes_from_the_managed_file(self) -> None:
        self.assertEqual(self.out["fileVrr"], {"eDP-1": 0, "DP-2": 2, 'desc:A "B" \\ C': 1})
        self.assertEqual(self.out["unmanagedVrr"], {}, "only a file with the marker is trusted")
        self.assertEqual([m["vrr"] for m in self.out["specWithFile"]], [0, None, 2])
        result = lua_expr(self.out["specWithFile"])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('output = "eDP-1", mode = "1920x1080@144.00Hz", position = "0x0", scale = 1, '
                      'transform = 0, disabled = false, vrr = 0', result.stdout)
        hdmi = [c for c in result.stdout.split("; ") if 'output = "HDMI-A-1"' in c]
        self.assertEqual(len(hdmi), 1)
        self.assertNotIn("vrr", hdmi[0])

    def test_every_preset_is_accepted_and_keeps_an_output(self) -> None:
        self.assertEqual(sorted(self.out["presets"]), ["extend", "external", "internal", "mirror"])
        for kind, spec in self.out["presets"].items():
            with self.subTest(kind=kind):
                self.assertTrue(any(m["enabled"] for m in spec))
                result = lua_expr(spec)
                self.assertEqual(result.returncode, 0, result.stderr)
        presets = self.out["presets"]
        self.assertEqual([m["name"] for m in presets["internal"] if m["enabled"]], ["eDP-1"])
        self.assertEqual([m["name"] for m in presets["external"] if m["enabled"]], ["HDMI-A-1", "DP-2"])
        mirror = {m["name"]: m for m in presets["mirror"]}
        self.assertEqual(mirror["HDMI-A-1"]["mirror"], "eDP-1")
        self.assertEqual(mirror["HDMI-A-1"]["mode"], "1920x1080@60.00Hz")
        self.assertEqual(mirror["DP-2"]["mode"], "1920x1080@60.00Hz")
        extend = {m["name"]: m["position"] for m in presets["extend"]}
        self.assertEqual(extend["eDP-1"], {"x": 0, "y": 0})
        self.assertEqual(extend["HDMI-A-1"], {"x": 1920, "y": 0})
        # DP-2 was off: its preferred size is unknown, so it follows HDMI-A-1.
        self.assertEqual(extend["DP-2"]["x"], 3840)

    def test_arrangement_and_guards(self) -> None:
        self.assertEqual(self.out["arrangement"][:2], ["left:HDMI-A-1", "right:eDP-1"])
        moved = {m["name"]: m["position"] for m in self.out["moved"]}
        self.assertEqual(moved["HDMI-A-1"], {"x": 0, "y": 1080})
        self.assertIsNone(self.out["lastOff"], "the last enabled output cannot be turned off")
        self.assertEqual(self.out["scales"], [1, 1.2, 1.25, 1.333333, 1.5, 1.6, 1.666667, 2, 2.4, 2.5, 3])


class GeneratorWiringTests(unittest.TestCase):
    def test_idle_marker_matches_generator(self) -> None:
        logic = (SETTINGS / "backends/IdleLogic.js").read_text(encoding="utf-8")
        source = IDLEGEN.read_text(encoding="utf-8")
        marker = next(line.split('"')[1] for line in logic.splitlines() if line.startswith("var IDLE_MARKER"))
        self.assertIn(f"MARKER = '{marker}'", source)

    def test_idle_options_are_valid_generator_timeouts(self) -> None:
        power = load(SETTINGS / "registry/power.json")
        idle = [e for e in power["entries"] if e["backend"] == "idle"]
        self.assertEqual([e["key"] for e in idle], ["idle.lockTimeout", "idle.dpmsTimeout", "idle.suspendTimeout"])
        for entry in idle:
            self.assertTrue(entry["risky"])
            values = [o["value"] for o in entry["options"]]
            self.assertEqual(values, [0, 60, 120, 300, 600, 900, 1800, 3600])
        for value in (60, 3600):
            result = subprocess.run([sys.executable, str(IDLEGEN), "--print", "--lock", str(value)],
                                    capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stderr)

    def test_backends_run_generators_by_argv(self) -> None:
        display = (SETTINGS / "backends/DisplayBackend.qml").read_text(encoding="utf-8")
        idle = (SETTINGS / "backends/IdleBackend.qml").read_text(encoding="utf-8")
        self.assertIn('Quickshell.shellPath("scripts/settings/monitorsgen.py")', display)
        self.assertIn('["hyprctl", "eval", generatorOut.text.trim()]', display)
        self.assertIn('["hyprctl", "-j", "monitors", "all"]', display)
        self.assertIn('Quickshell.shellPath("scripts/settings/idlegen.py")', idle)
        self.assertIn('.concat(["--restart"])', idle)
        power_page = (SETTINGS / "pages/PowerPage.qml").read_text(encoding="utf-8")
        self.assertIn("IdleLogic.applyArgs(", power_page)
        displays_page = (SETTINGS / "pages/DisplaysPage.qml").read_text(encoding="utf-8")
        self.assertIn('displaysPage.spec, "write", true)', displays_page)
        self.assertNotIn("hyprctl reload", display + idle)

    def test_risky_layout_and_capability_gated_actions(self) -> None:
        displays = {e["key"]: e for e in load(SETTINGS / "registry/displays.json")["entries"]}
        self.assertTrue(displays["display.monitors"]["risky"])
        self.assertEqual(displays["action.displays.replaceMonitors"]["visibleWhen"], {"capability": "monitorsFileUnmanaged"})
        self.assertEqual(displays["display.presets"]["visibleWhen"], {"capability": "multiMonitor"})
        power = {e["key"]: e for e in load(SETTINGS / "registry/power.json")["entries"]}
        self.assertEqual(power["action.power.applyIdle"]["visibleWhen"], {"capability": "idleOutOfSync"})
        self.assertEqual(power["action.power.replaceIdle"]["visibleWhen"], {"capability": "idleUnmanaged"})
        for key in ("battery.low", "battery.critical", "battery.full", "battery.automaticSuspend", "battery.suspend"):
            self.assertEqual(power[key]["visibleWhen"], {"capability": "battery"})
        lock_keys = [k for k in power if k.startswith("lock.")]
        self.assertEqual(len(lock_keys), 10)


if __name__ == "__main__":
    unittest.main()
