"""AnimationBackend under the sandboxed harness (tests/harness/drivers/animation-backend.qml).

The backend runs against the hyprctl stub and a python3 shim that logs (and
can force the exit code of) animationsgen.py calls, so the test counts
generator calls, evals and reloads from the logs and reads the generated
file. Acceptance of plan A1: invalid -> nothing persisted; Hyprland rejecting
the value or a generator failure -> one reload; not watched -> one reload;
autoreload -> none; two writes inside the reload grace -> confirmed
against the last one; unchanged -> no generator call; preset -> one call and one
eval; disable/enable keeps the tuple; Game Mode notes; a configreloaded while
the generator runs keeps the shown value; succeeded() when only a default or
a status note changes; the animationsLoaded confirmation (a failed read is
retried, a parsed mismatch drops it) and the capability without the require.
The live Hyprland session is never contacted.
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
            "disableEnable", "defaultPreset", "gameMode", "reloadDuringApply", "baseArrives", "twoWritesInGrace",
            "transientRead", "notLoaded", "noRequire"}
# Fails `hyprctl -j animations` once while $HYPRCTL_ANIMATIONS_FAIL exists, else runs the stub.
HYPRCTL_WRAPPER = """#!/bin/sh
if [ "$*" = "-j animations" ] && [ -n "$HYPRCTL_ANIMATIONS_FAIL" ] && [ -f "$HYPRCTL_ANIMATIONS_FAIL" ]; then
    rm -f "$HYPRCTL_ANIMATIONS_FAIL"
    [ -n "$HYPRCTL_LOG" ] && printf '%s\\n' "$*" >> "$HYPRCTL_LOG"
    echo "transient failure" >&2
    exit 1
fi
exec "$(dirname "$0")/hyprctl-stub" "$@"
"""


class AnimationBackendHarnessTest(unittest.TestCase):
    def test_writes_failures_and_reloads(self) -> None:
        with tempfile.TemporaryDirectory() as out:
            out_dir = Path(out)
            bin_dir = out_dir / "bin"
            bin_dir.mkdir()
            shutil.copy(STUBS / "python3", bin_dir / "python3")
            shutil.copy(STUBS / "hyprctl", bin_dir / "hyprctl-stub")
            (bin_dir / "hyprctl").write_text(HYPRCTL_WRAPPER, encoding="utf-8")
            for name in ("hyprctl", "hyprctl-stub", "python3"):
                (bin_dir / name).chmod(0o755)
            fixtures = out_dir / "fixtures"
            fixtures.mkdir()
            for name in ("hyprland-options.json", "hyprctl-devices.json", "hyprctl-monitors-all.json",
                         "hyprctl-animations.json", "hyprbase-sample.json"):
                shutil.copy(FIXTURES / name, fixtures / name)
            # Hyprland as it looks once it loaded the writes the later
            # confirmations compare (a confirmation checks every managed card):
            # windowsIn, border ("reloadDuringApply") and layersIn ("transientRead");
            # windowsOut keeps its old value for the "not loaded" scenario.
            animations = json.loads((fixtures / "hyprctl-animations.json").read_text(encoding="utf-8"))
            for item in animations[0]:
                if item["name"] == "windowsIn":
                    item.update({"overridden": True, "bezier": "emphasizedDecel", "enabled": True, "speed": 2.0,
                                 "style": "popin 85%"})
                if item["name"] == "border":
                    item.update({"overridden": True, "bezier": "emphasizedDecel", "enabled": True, "speed": 5.0})
                if item["name"] == "layersIn":
                    item.update({"overridden": True, "bezier": "emphasizedDecel", "enabled": True, "speed": 1.5,
                                 "style": "popin 80%"})
            (fixtures / "hyprctl-animations.json").write_text(json.dumps(animations), encoding="utf-8")
            result = subprocess.run(
                ["bash", str(RUN), "--driver", str(DRIVER), "--renderer", "software", "--hyprland-stub",
                 "--out", out, "--timeout", "240",
                 "--env", f"PATH={bin_dir}:/usr/bin:/bin",
                 "--env", f"HYPRCTL_FIXTURES={fixtures}",
                 "--env", r"HYPRCTL_FAIL_MATCH=speed = 7\.77",
                 "--env", f"PYTHON3_SHIM_LOG={out_dir / 'python3.log'}",
                 "--env", f"PYTHON3_SHIM_FAIL={out_dir / 'shim-fail'}",
                 "--env", f"PYTHON3_SHIM_DELAY={out_dir / 'shim-delay'}",
                 "--env", f"HYPRCTL_ANIMATIONS_FAIL={out_dir / 'animations-fail'}",
                 "--env", f"ANIM_BASE_FIXTURE={fixtures / 'hyprbase-sample.json'}"],
                capture_output=True, text=True, timeout=330,
            )
            if result.returncode == 77:
                self.skipTest(result.stderr.strip() or "harness prerequisites missing")
            # run.sh can fail before the app starts: show why instead of a FileNotFoundError.
            run_output = f"run.sh exited with {result.returncode}\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
            log_path = out_dir / "harness.log"
            self.assertTrue(log_path.is_file(), f"harness.log is missing\n{run_output}")
            harness_log = log_path.read_text(encoding="utf-8", errors="replace")
            calls_path = out_dir / "hyprctl.log"
            calls = calls_path.read_text(encoding="utf-8") if calls_path.is_file() else ""
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
