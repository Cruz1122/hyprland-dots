"""Shell motion settings (appearance.animations) with the real Appearance singleton.

tests/harness/drivers/motion-scale.qml runs in the sandboxed harness with a
config.json seeded with durationScale 0.5, then switches reduceMotion on and
goes back to the normal speed through Config.options (live, like the settings
app does). The pure helper is covered by tests/qml_settings/tst_MotionScale.qml.
"""
from __future__ import annotations

import json
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RUN = ROOT / "scripts/settings-harness/run.sh"
DRIVER = ROOT / "tests/harness/drivers/motion-scale.qml"
DEFAULT_CONFIG = ROOT / "config/illogical-impulse/config.json"
MARKER = "[harness:report] "
PRESETS = {
    "elementMove": 500, "elementMoveSmall": 350, "elementMoveEnter": 400, "elementMoveExit": 200,
    "elementMoveFast": 200, "elementResize": 300, "clickBounce": 400, "scroll": 200, "menuDecel": 350,
}


def run_harness(args: list[str], out: str, timeout: int = 240) -> tuple[subprocess.CompletedProcess, str]:
    result = subprocess.run(["bash", str(RUN), *args, "--renderer", "software", "--out", out],
                            capture_output=True, text=True, timeout=timeout)
    log_path = Path(out) / "harness.log"
    log = log_path.read_text(encoding="utf-8", errors="replace") if log_path.exists() else ""
    return result, log


def events_of(log: str) -> list[dict]:
    return [json.loads(line[line.index(MARKER) + len(MARKER):]) for line in log.splitlines() if MARKER in line]


class MotionScaleDriverTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            config = json.loads(DEFAULT_CONFIG.read_text(encoding="utf-8"))
            config.setdefault("appearance", {})["animations"] = {"durationScale": 0.5}
            seed = Path(tmp) / "seed.json"
            seed.write_text(json.dumps(config), encoding="utf-8")
            out = Path(tmp) / "out"
            # The driver changes the config on purpose: strict mode still fails
            # on QML warnings, and the writes are checked below.
            cls.result, cls.log = run_harness(
                ["--driver", str(DRIVER), "--strict", "--allow-config-writes", "--config", str(seed),
                 "--timeout", "90"], str(out), timeout=150)
            after = out / "config.after.json"
            cls.after = json.loads(after.read_text(encoding="utf-8")) if after.exists() else None
        if cls.result.returncode == 77:
            raise unittest.SkipTest(cls.result.stderr.strip() or "harness prerequisites missing")
        cls.events = events_of(cls.log)
        cls.context = cls.result.stdout + cls.result.stderr + cls.log[-3000:]

    def motion(self, label: str) -> dict:
        found = [e for e in self.events if e.get("type") == "motion" and e.get("label") == label]
        self.assertEqual(len(found), 1, self.context)
        return found[0]

    def finish(self, label: str) -> dict:
        found = [e for e in self.events if e.get("type") == "finish" and e.get("label") == label]
        self.assertEqual(len(found), 1, self.context)
        return found[0]

    def test_run_passes_and_completes(self) -> None:
        self.assertFalse([e for e in self.events if e.get("type") == "fatal"], self.context)
        self.assertIn({"type": "done"}, self.events, self.context)
        self.assertEqual(self.result.returncode, 0, self.context)

    def test_half_scale_halves_durations_and_doubles_velocity(self) -> None:
        state = self.motion("seeded")
        self.assertEqual(state["factor"], 0.5)
        self.assertEqual(state["elementMove"], 250)
        for name, base in PRESETS.items():
            self.assertEqual(state[name], round(base * 0.5), name)
        self.assertEqual(state["elementMoveVelocity"], 1300)
        self.assertEqual(state["elementMoveFastVelocity"], 1700)
        self.assertEqual(state["heldFactoryDuration"], 250)
        self.assertEqual(state["scaledHelper520"], 260)
        # The raw curve constants stay raw; readers use the scaled presets.
        self.assertEqual(state["rawCurveDuration"], 500)

    def test_reduce_motion_uses_one_ms_and_instant_velocity(self) -> None:
        state = self.motion("reduced")
        self.assertEqual(state["factor"], 0)
        for name in PRESETS:
            self.assertEqual(state[name], 1, name)
        self.assertEqual(state["elementMoveVelocity"], 1e6)
        self.assertEqual(state["elementMoveFastVelocity"], 1e6)
        # An animation created earlier from a factory follows the change live.
        self.assertEqual(state["heldFactoryDuration"], 1)
        self.assertEqual(state["scaledHelper520"], 1)

    def test_reduced_factory_animations_finish_asynchronously(self) -> None:
        for label in ("elementMoveFast", "elementMove"):
            probe = self.finish(label)
            self.assertEqual(probe["duration"], 1, probe)
            self.assertEqual(probe["duringStart"], 0, probe)
            self.assertTrue(probe["runningAfterStart"], probe)
            self.assertEqual(probe["finishedLater"], 1, probe)

    def test_zero_duration_control_finishes_inside_start(self) -> None:
        # Why the floor is 1 ms: Qt finishes a 0 ms animation inside start().
        probe = self.finish("zeroControl")
        self.assertEqual(probe["duration"], 0, probe)
        self.assertEqual(probe["duringStart"], 1, probe)

    def test_back_to_normal_restores_base_values(self) -> None:
        state = self.motion("normal")
        self.assertEqual(state["factor"], 1)
        for name, base in PRESETS.items():
            self.assertEqual(state[name], base, name)
        self.assertEqual(state["elementMoveVelocity"], 650)
        self.assertEqual(state["heldFactoryDuration"], 500)
        self.assertIsNotNone(self.after, self.context)
        self.assertEqual(self.after["appearance"]["animations"], {"durationScale": 1, "reduceMotion": False})


class MotionKeysAbsentTest(unittest.TestCase):
    def test_settings_app_loads_strict_without_the_keys(self) -> None:
        config = json.loads(DEFAULT_CONFIG.read_text(encoding="utf-8"))
        self.assertNotIn("animations", config.get("appearance", {}),
                         "the packaged config must exercise the missing-key path")
        with tempfile.TemporaryDirectory() as out:
            result, log = run_harness(
                ["--strict", "--hyprland-stub", "--pages", "animations", "--sizes", "1100x760",
                 "--env", "II_SETTINGS_PAGE=animations",
                 "--env", "II_SETTINGS_KEY=appearance.animations.reduceMotion", "--timeout", "120"], out)
            if result.returncode == 77:
                self.skipTest(result.stderr.strip() or "harness prerequisites missing")
            report_path = Path(out) / "report.json"
            report = json.loads(report_path.read_text(encoding="utf-8")) if report_path.exists() else {}
        context = result.stdout + result.stderr + log[-3000:]
        self.assertEqual(result.returncode, 0, context)
        self.assertTrue(report.get("ok"), context)
        self.assertEqual(report.get("appWarnings"), [], context)
        self.assertEqual(report.get("config", {}).get("changed"), [], context)
        self.assertFalse(report.get("config", {}).get("rewritten"), context)


if __name__ == "__main__":
    unittest.main()
