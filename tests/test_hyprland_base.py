"""HyprlandBackend defaults from the dotfiles' base and Game Mode's stored values.

Runs tests/harness/drivers/hyprland-base.qml in the sandboxed harness with the
Hyprland stub. `-j descriptions` comes from a copy of the options fixture whose
values stand for Game Mode's live state, so the stored value differs from the
live one; see the driver for the scenario.
"""
from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RUN = ROOT / "scripts/settings-harness/run.sh"
DRIVER = ROOT / "tests/harness/drivers/hyprland-base.qml"
FIXTURES = ROOT / "tests/fixtures"
MARKER = "[harness:report] "

# Live values while Game Mode is on (it sets them in shellOverrides/main.lua),
# plus a compiled default the dotfiles never set.
LIVE = {
    "animations:enabled": False,
    "decoration:blur:enabled": False,
    "general:gaps_in": 0,
    "general:gaps_out": 0,
    "decoration:rounding": 0,
    "decoration:inactive_opacity": 0.85,
}


class HyprlandBaseTest(unittest.TestCase):
    def test_base_defaults_and_game_mode_stored_values(self) -> None:
        with tempfile.TemporaryDirectory() as out:
            fixtures = Path(out) / "fixtures"
            fixtures.mkdir()
            for name in ("hyprctl-devices.json", "hyprctl-monitors-all.json", "hyprctl-animations.json"):
                shutil.copy(FIXTURES / name, fixtures / name)
            options = json.loads((FIXTURES / "hyprland-options.json").read_text(encoding="utf-8"))
            for name, value in LIVE.items():
                options[name]["default"] = value
            (fixtures / "hyprland-options.json").write_text(json.dumps(options), encoding="utf-8")
            result = subprocess.run(
                ["bash", str(RUN), "--driver", str(DRIVER), "--renderer", "software", "--hyprland-stub",
                 "--strict", "--allow-config-writes", "--out", out, "--timeout", "120",
                 "--env", f"HYPRCTL_FIXTURES={fixtures}"],
                capture_output=True, text=True, timeout=180,
            )
            if result.returncode == 77:
                self.skipTest(result.stderr.strip() or "harness prerequisites missing")
            log = (Path(out) / "harness.log").read_text(encoding="utf-8", errors="replace")
            calls = (Path(out) / "hyprctl.log").read_text(encoding="utf-8")
        events = [json.loads(line[line.index(MARKER) + len(MARKER):])
                  for line in log.splitlines() if MARKER in line]
        self.assertFalse([e for e in events if e.get("type") == "fatal"], log[-3000:])
        checks = [e for e in events if e.get("type") == "check"]
        self.assertEqual(len(checks), 35, result.stdout + log[-3000:])
        for check in checks:
            with self.subTest(check=check["name"]):
                self.assertEqual(check["actual"], check["expected"], check)
        self.assertTrue(any(e.get("type") == "done" for e in events), log[-3000:])
        self.assertFalse([c for c in calls.splitlines() if c.startswith("eval")], calls)
        # --strict: no QML warning, including when the base cannot be read.
        self.assertEqual(result.returncode, 0, result.stdout + log[-3000:])


if __name__ == "__main__":
    unittest.main()
