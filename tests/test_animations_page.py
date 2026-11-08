"""The Animations page in the sandboxed harness (tests/harness/drivers/animations-page.qml).

The real settings window runs with the hyprctl stub and the python3 shim
(tests/harness/stubs) first on PATH, so the driver counts generator calls,
evals and reloads from their logs and reads the generated file. Plan v2,
track B1: the widgets reach the backend helpers through
SettingsStore.backends.animation; a preset is 1 generator call, 1 eval and at
most 1 reload; Default empties the animations and keeps the curves; Undo of a
preset over a custom state restores the cards in one batch; Tab reaches the
controls of folded and unfolded cards; a search hit unfolds a card; a curve
that a card uses cannot be deleted; a user spring is only renamed; the Quick
alias is the same preset row; reduceMotion stops automatic replays but
not ▶ (every start is recorded, no timed sampling); without the
animationsLoaded capability every animation row and [Apply Minimal] is
disabled with its reason and a write runs nothing; an unavailable backend
shows no "Now:" note on the preset and disables [Apply Minimal]; a second
preset renames the Undo bar; a spring shows its own settle time; [Apply Minimal] writes the
Minimal preset; Game Mode shows its note and never "Requires …"; a card unfolded at
760, 1100 and 1600 px never overlaps the next row. The live Hyprland session
is never contacted.
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
DRIVER = ROOT / "tests/harness/drivers/animations-page.qml"
STUBS = ROOT / "tests/harness/stubs"
FIXTURES = ROOT / "tests/fixtures"
MARKER = "[harness:report] "
REQUIRED = [
    "start: the Animations page opens",
    "helpers: the rows exist",
    "helpers: summaryParts reaches the card",
    "helpers: the summary is translated and joined",
    "helpers: curveCatalog reaches the card",
    "helpers: styleOptions reaches the card",
    "helpers: presets reach the preset row",
    "helpers: curveUsage reaches the curve library",
    "helpers: panel card summaries leave out the style",
    "helpers: panel cards and details have no style control",
    "tab-order: a folded card",
    "tab-order: Space unfolds the card",
    "unfolded: the controls show the card's value",
    "tab-order: an unfolded card",
    "tab-order: the focus ring shows",
    "tab-order: Enter folds the card",
    "tab-order: the card has an accessible name and description",
    "search: the card is a search result",
    "search: revealing the card unfolds it",
    "not-loaded: the rows start enabled with the loader",
    "not-loaded: every animation row is disabled with the reason",
    "not-loaded: [Apply Minimal] is disabled with the reason",
    "not-loaded: a write is refused and runs nothing",
    "not-loaded: the loader back enables the rows again",
    "unavailable: with the backend the preset shows its note",
    "unavailable: the preset shows — and no Now note",
    "unavailable: [Apply Minimal] is disabled",
    "unavailable: the backend back restores the note and the action",
    "loaded: Hyprland reports the first written card",
    "loaded: the card is back to the dotfiles value",
    "curve-add: the editor opens with a generated name",
    "curve-add: the curve is saved",
    "curve-spring: a spring opens without the bezier editor",
    "curve-spring: renaming keeps the spring",
    "curve-spring: the spring is removed again",
    "preset: starts from Default",
    "preset: one generator call, one eval, at most one reload",
    "preset: the row shows the preset",
    "preset: no Undo bar over a preset",
    "preset: every card is in the file",
    "preset: the Quick alias is a preset row",
    "preset: back on the Animations page",
    "default: no animation lines are left",
    "default: the curves stay",
    "default: one generator call",
    "default: the row shows Default",
    "apply-minimal: the button writes the Minimal preset",
    "apply-minimal: Default again",
    "undo: a card change makes the state custom",
    "undo: a preset over a custom state shows Undo",
    "undo: a second preset renames the Undo bar",
    "undo: the second preset is applied",
    "undo: one batch",
    "undo: the previous cards are back",
    "undo: the bar goes away",
    "delete-used: the delete is refused",
    "delete-used: the library says who uses it",
    "reduce-motion: a changed control does not play the preview",
    "reduce-motion: ▶ plays it",
    "reduce-motion: without it a change replays the preview",
    "spring: the card shows the spring's own time",
    "game-mode: the cards show the note and no Requires",
    "game-mode: the page banner shows",
    "game-mode: the note goes away with Game Mode",
    "shots: rows do not overlap with a card unfolded",
    "shots: the unfolded card fits its row",
]


class AnimationsPageHarnessTest(unittest.TestCase):
    def test_animations_page(self) -> None:
        keep = os.environ.get("ANIMATIONS_PAGE_OUT")
        with tempfile.TemporaryDirectory() as tmp:
            # Everything the sandbox reads or writes lives under --out: run.sh
            # binds it, while the rest of /tmp is replaced inside the sandbox.
            out_dir = Path(keep) if keep else Path(tmp)
            out_dir.mkdir(parents=True, exist_ok=True)
            bin_dir = out_dir / "bin"
            bin_dir.mkdir(exist_ok=True)
            shutil.copy(STUBS / "python3", bin_dir / "python3")
            shutil.copy(STUBS / "hyprctl", bin_dir / "hyprctl")
            for name in ("hyprctl", "python3"):
                (bin_dir / name).chmod(0o755)
            # Hyprland as it looks after the driver's first card write
            # ("loaded" step): the backend confirms the file once against
            # `hyprctl -j animations` and warns on a difference.
            fixtures = out_dir / "fixtures"
            fixtures.mkdir(exist_ok=True)
            for name in ("hyprland-options.json", "hyprctl-devices.json", "hyprctl-monitors-all.json",
                         "hyprctl-animations.json"):
                shutil.copy(FIXTURES / name, fixtures / name)
            animations = json.loads((fixtures / "hyprctl-animations.json").read_text(encoding="utf-8"))
            for item in animations[0]:
                if item["name"] == "windowsIn":
                    item.update({"overridden": True, "bezier": "emphasizedDecel", "enabled": True, "speed": 2.0,
                                 "style": "popin 85%"})
            (fixtures / "hyprctl-animations.json").write_text(json.dumps(animations), encoding="utf-8")
            shots = out_dir / "shots"
            shots.mkdir(exist_ok=True)
            result = subprocess.run(
                ["bash", str(RUN), "--strict", "--allow-config-writes", "--hyprland-stub", "--driver", str(DRIVER),
                 "--renderer", "software", "--out", str(out_dir), "--sizes", "1100x760", "--timeout", "280",
                 "--env", f"PATH={bin_dir}:/usr/bin:/bin",
                 "--env", f"HYPRCTL_FIXTURES={fixtures}",
                 "--env", f"PYTHON3_SHIM_LOG={out_dir / 'python3.log'}",
                 "--env", f"SHOT_DIR={shots}"],
                capture_output=True, text=True, timeout=360,
            )
            if result.returncode == 77:
                self.skipTest(result.stderr.strip() or "harness prerequisites missing")
            log_path = out_dir / "harness.log"
            run_output = f"run.sh exited with {result.returncode}\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
            self.assertTrue(log_path.is_file(), f"harness.log is missing\n{run_output}")
            log = log_path.read_text(encoding="utf-8", errors="replace")
            pngs = sorted(p.name for p in shots.glob("*.png"))
        events = [json.loads(line[line.index(MARKER) + len(MARKER):]) for line in log.splitlines() if MARKER in line]
        context = result.stdout + log[-4000:]
        self.assertFalse([e for e in events if e.get("type") == "fatal"], context)
        checks = [e for e in events if e.get("type") == "check"]
        for step in REQUIRED:
            with self.subTest(step=step):
                matching = [c for c in checks if c["step"] == step]
                self.assertTrue(matching, f"missing check {step!r}\n{context}")
                self.assertTrue(all(c["ok"] for c in matching), matching)
        self.assertEqual(len([c for c in checks if c["step"] == "shots: rows do not overlap with a card unfolded"]), 3)
        self.assertEqual(pngs, ["animations-unfolded-1100x760.png", "animations-unfolded-1600x900.png",
                                "animations-unfolded-760x720.png"])
        self.assertEqual([e.get("failures") for e in events if e.get("type") == "done"], [0], context)
        self.assertEqual(result.returncode, 0, run_output + log[-3000:])


if __name__ == "__main__":
    unittest.main()
