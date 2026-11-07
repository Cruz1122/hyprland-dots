"""Game Mode state follows its own override, checked in the sandboxed harness."""
from __future__ import annotations

import json
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RUN = ROOT / "scripts/settings-harness/run.sh"
DRIVER = ROOT / "tests/harness/drivers/game-mode-state.qml"
MARKER = "[harness:report] "


class GameModeStateTest(unittest.TestCase):
    def test_toggle_follows_game_mode_override_not_effective_animations(self) -> None:
        with tempfile.TemporaryDirectory() as out:
            result = subprocess.run(
                ["bash", str(RUN), "--driver", str(DRIVER), "--renderer", "software",
                 "--out", out, "--timeout", "90"],
                capture_output=True, text=True, timeout=150,
            )
            if result.returncode == 77:
                self.skipTest(result.stderr.strip() or "harness prerequisites missing")
            log = (Path(out) / "harness.log").read_text(encoding="utf-8", errors="replace")
        events = [json.loads(line[line.index(MARKER) + len(MARKER):])
                  for line in log.splitlines() if MARKER in line]
        steps = [event for event in events if event.get("type") == "gamemode"]
        self.assertEqual(len(steps), 6, result.stdout + log[-2000:])
        for step in steps:
            self.assertEqual(step["actual"], step["expected"], step)


if __name__ == "__main__":
    unittest.main()
