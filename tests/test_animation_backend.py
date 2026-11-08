"""AnimationBackend under the sandboxed harness (tests/harness/drivers/animation-backend.qml).

The backend runs against the hyprctl stub and a python3 shim that logs (and
can force the exit code of) animationsgen.py calls, so the test counts
generator calls, evals and reloads from the logs and reads the generated
file. Acceptance of plan A1: invalid -> nothing persisted; Hyprland rejecting
the value or a generator failure -> one reload; not watched -> one reload;
autoreload -> none; two writes inside the reload grace -> confirmed
against the last one; unchanged -> no generator call; preset -> one call and one
eval; disable/enable keeps the tuple; Game Mode notes; the animationsLoaded
confirmation. The live Hyprland session is never contacted.
"""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RUN = ROOT / "scripts/settings-harness/run.sh"
DRIVER = ROOT / "tests/harness/drivers/animation-backend.qml"
STUBS = ROOT / "tests/harness/stubs"
FIXTURES = ROOT / "tests/fixtures"
MARKER = "[harness:report] "
EXPECTED = {"unwatched", "autoreload", "unchanged", "invalid", "rejected", "generatorFailure", "preset",
            "disableEnable", "defaultPreset", "gameMode", "twoWritesInGrace", "notLoaded"}


class AnimationBackendHarnessTest(unittest.TestCase):
    def test_writes_failures_and_reloads(self) -> None:
        with tempfile.TemporaryDirectory() as out:
            out_dir = Path(out)
            bin_dir = out_dir / "bin"
            bin_dir.mkdir()
            for name in ("hyprctl", "python3"):
                shutil.copy(STUBS / name, bin_dir / name)
                (bin_dir / name).chmod(0o755)
            fixtures = out_dir / "fixtures"
            fixtures.mkdir()
            for name in ("hyprland-options.json", "hyprctl-devices.json", "hyprctl-monitors-all.json",
                         "hyprctl-animations.json", "hyprbase-sample.json"):
                shutil.copy(FIXTURES / name, fixtures / name)
            # Hyprland as it looks once it loaded the first write (windowsIn);
            # windowsOut keeps its old value for the "not loaded" scenario.
            animations = json.loads((fixtures / "hyprctl-animations.json").read_text(encoding="utf-8"))
            for item in animations[0]:
                if item["name"] == "windowsIn":
                    item.update({"overridden": True, "bezier": "emphasizedDecel", "enabled": True, "speed": 2.0,
                                 "style": "popin 85%"})
            (fixtures / "hyprctl-animations.json").write_text(json.dumps(animations), encoding="utf-8")
            result = subprocess.run(
                ["bash", str(RUN), "--driver", str(DRIVER), "--renderer", "software", "--hyprland-stub",
                 "--out", out, "--timeout", "150",
                 "--env", f"PATH={bin_dir}:/usr/bin:/bin",
                 "--env", f"HYPRCTL_FIXTURES={fixtures}",
                 "--env", r"HYPRCTL_FAIL_MATCH=speed = 7\.77",
                 "--env", f"PYTHON3_SHIM_LOG={out_dir / 'python3.log'}",
                 "--env", f"PYTHON3_SHIM_FAIL={out_dir / 'shim-fail'}",
                 "--env", f"ANIM_BASE_FIXTURE={fixtures / 'hyprbase-sample.json'}"],
                capture_output=True, text=True, timeout=240,
            )
            if result.returncode == 77:
                self.skipTest(result.stderr.strip() or "harness prerequisites missing")
            harness_log = (out_dir / "harness.log").read_text(encoding="utf-8", errors="replace")
            calls = (out_dir / "hyprctl.log").read_text(encoding="utf-8")
        events = [json.loads(line[line.index(MARKER) + len(MARKER):])
                  for line in harness_log.splitlines() if MARKER in line]
        self.assertFalse([e for e in events if e.get("type") == "fatal"], harness_log[-3000:])
        scenarios = {e["name"]: e for e in events if e.get("type") == "scenario"}
        self.assertEqual(set(scenarios), EXPECTED, result.stdout + harness_log[-3000:])
        for name, event in scenarios.items():
            with self.subTest(scenario=name):
                self.assertEqual(event["actual"], event["expected"], calls)
        self.assertTrue(any(e.get("type") == "done" for e in events), harness_log[-3000:])
        self.assertEqual(result.returncode, 0, result.stdout + harness_log[-3000:])


class StoreWiringTest(unittest.TestCase):
    def test_store_passes_the_hyprland_base_to_the_animation_backend(self) -> None:
        # The driver above uses the baseFixture seam, so only this pins the
        # production path: hyprbase.py runs once, in HyprlandBackend.
        store = (ROOT / "config/quickshell/ii/modules/settings/core/SettingsStore.qml").read_text(encoding="utf-8")
        self.assertRegex(store, r"AnimationBackend\s*\{[^}]*sharedBase:\s*hyprlandBackend\.basePayload")
        backend = (ROOT / "config/quickshell/ii/modules/settings/backends/AnimationBackend.qml").read_text(encoding="utf-8")
        self.assertNotIn("scripts/settings/hyprbase.py", backend, "AnimationBackend must not run hyprbase.py itself")


if __name__ == "__main__":
    unittest.main()
