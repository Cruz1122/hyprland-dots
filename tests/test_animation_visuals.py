"""Animation visuals (curve thumbnails, picker, editor, previews) in the strict harness.

Runs tests/harness/drivers/animation-visuals.qml, which renders a gallery of
every component and state at 760 and 1100 px in a dark and a light theme,
then checks the picker's keyboard navigation, the editor's clamping,
validation, bound points and ball track, the previews' frame, idle state,
play()/replay() rules and geometry, and plays one preview to its end. To look at the screenshots:
    scripts/settings-harness/run.sh --strict --driver tests/harness/drivers/animation-visuals.qml \
        --sizes 1100x760 --out DIR
"""
from __future__ import annotations

import json
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RUN = ROOT / "scripts/settings-harness/run.sh"
DRIVER = ROOT / "tests/harness/drivers/animation-visuals.qml"
MARKER = "[harness:report] "
SHOTS = 2 * 2 * 5  # widths x themes x gallery sections


class AnimationVisualsTest(unittest.TestCase):
    def test_gallery_keyboard_clamping_and_playback(self) -> None:
        with tempfile.TemporaryDirectory() as out:
            result = subprocess.run(
                ["bash", str(RUN), "--strict", "--driver", str(DRIVER), "--sizes", "1100x760",
                 "--out", out, "--timeout", "150"],
                capture_output=True, text=True, timeout=240,
            )
            if result.returncode == 77:
                self.skipTest(result.stderr.strip() or "harness prerequisites missing")
            log = (Path(out) / "harness.log").read_text(encoding="utf-8", errors="replace")
            events = [json.loads(line[line.index(MARKER) + len(MARKER):])
                      for line in log.splitlines() if MARKER in line]
            pages = [event for event in events if event.get("type") == "page"]
            for page in pages:
                self.assertTrue(Path(page["file"]).is_file(), page["file"])
        context = result.stdout + log[-3000:]
        self.assertEqual(result.returncode, 0, context)
        self.assertEqual(len(pages), SHOTS, context)
        for page in pages:
            self.assertTrue(page["saved"], page)
            self.assertEqual(page["overflowX"], [], page)
        checks = [event for event in events if event.get("type") == "check"]
        failed = [check for check in checks if not check["ok"]]
        self.assertEqual(failed, [], context)
        names = {check["name"] for check in checks}
        mapped = [name for name in names if name.endswith("maps progress through CurveMath")]
        self.assertEqual(len(mapped), 5, mapped)
        for required in ("picker: Tab enters the group on the selected curve", "picker: Tab leaves the group",
                         "picker: Space chooses the focused curve", "picker: Enter chooses the focused curve",
                         "picker: choosing the unknown item keeps the value",
                         "editor: dragging past the top-left clamps the first point to x 0, y 2",
                         "editor: dragging past the bottom-right clamps the second point to x 1, y -1",
                         "editor: x out of [0, 1] is invalid and not applied", "editor: steps stop at x 1",
                         "preview: played to its end once", "preview: no automatic replay with reduceMotion",
                         "picker: a user label with markup is shown as plain text",
                         "picker: an unknown name with markup is shown as plain text",
                         "editor: a user label with markup is shown as plain text in Start from",
                         "preview: a decelerating curve is not linear",
                         "preview: slide left starts left of its place and follows the value",
                         "preview: slide with no direction comes from the nearest edge (bottom)",
                         "preview: windowsOut goes from opaque and full size to transparent at 90%",
                         "preview: workspaces slidefade 50% offsets the incoming workspace by half the screen",
                         "preview: idle shows the end state",
                         "preview: a disabled card shows the end state without play()",
                         "preview: disabling it while it plays shows the end state",
                         "preview: play() plays even with reduceMotion", "preview: play() takes no automatic flag",
                         "preview: replay() restarts from the start", "preview: play() restarts from the start",
                         "preview: the rounded frame is drawn above a mini screen clipped inside it",
                         "editor: an overshooting curve keeps the ball inside the track",
                         "editor: an edit changes the edited copy, not the bound points",
                         "editor: changing the bound points after an edit shows them",
                         "editor: a negative x is invalid and not applied"):
            self.assertIn(required, names)
        self.assertTrue(any(event.get("type") == "done" for event in events), context)


if __name__ == "__main__":
    unittest.main()
