"""Comprehension layer of the settings app in the sandboxed harness.

tests/harness/drivers/comprehension.qml checks "Now: …" option notes and
slider captions, help search and the help toggle by keyboard, the
"Requires …" link (said once to screen readers), the 2-chip limit, the
italic status note of a row paused by Game Mode and the navigation (modified
count reserved at 0 and described, no elided page title, a list width that
counts and selection do not change), all with the fake hyprctl; without
Hyprland, on the Windows, Input and Animations pages, one banner per section
that shares the reason and "—" with no live control instead of made-up
values (Input covers list and text rows). See docs/settings.md "Rows and
pages".
"""
from __future__ import annotations

import json
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RUN = ROOT / "scripts/settings-harness/run.sh"
DRIVER = ROOT / "tests/harness/drivers/comprehension.qml"
MARKER = "[harness:report] "


def run_driver(*extra: str) -> tuple[subprocess.CompletedProcess, list[dict], str]:
    with tempfile.TemporaryDirectory() as out:
        result = subprocess.run(
            ["bash", str(RUN), "--strict", "--driver", str(DRIVER), "--renderer", "software",
             "--out", out, "--timeout", "150", *extra],
            capture_output=True, text=True, timeout=240,
        )
        log_path = Path(out) / "harness.log"
        log = log_path.read_text(encoding="utf-8", errors="replace") if log_path.is_file() else ""
    events = [json.loads(line[line.index(MARKER) + len(MARKER):]) for line in log.splitlines() if MARKER in line]
    return result, events, log


class SettingsComprehensionTest(unittest.TestCase):
    def assert_run(self, result: subprocess.CompletedProcess, events: list[dict], log: str,
                   mode: str, required_steps: list[str]) -> None:
        if result.returncode == 77:
            self.skipTest(result.stderr.strip() or "harness prerequisites missing")
        context = result.stdout + log[-3000:]
        self.assertFalse([e for e in events if e.get("type") == "fatal"], context)
        start = [e for e in events if e.get("type") == "start"]
        self.assertEqual([e.get("mode") for e in start], [mode], context)
        checks = [e for e in events if e.get("type") == "check"]
        for step in required_steps:
            with self.subTest(step=step):
                matching = [c for c in checks if c["step"] == step]
                self.assertTrue(matching, f"missing check {step!r}\n{context}")
                self.assertTrue(all(c["ok"] for c in matching), matching)
        self.assertEqual([e.get("failures") for e in events if e.get("type") == "done"], [0], context)
        self.assertEqual(result.returncode, 0, context)

    def test_help_search_keyboard_toggle_and_requires_link(self) -> None:
        result, events, log = run_driver("--hyprland-stub")
        self.assert_run(result, events, log, "hyprland", [
            "option-texts: the pages are not created yet",
            "option-texts: the selected option's description shows as Now: …",
            "option-texts: the accessible description includes it",
            "option-texts: the slider shows minLabel and maxLabel under the track",
            "option-texts: the default tick is drawn when the default is known",
            "option-texts: the reset text names the default",
            "help-search: word found only in a help text",
            "help-search: reveal highlights the row and opens its help",
            "help-keys: the toggle takes keyboard focus",
            "help-keys: accessible name",
            "help-keys: collapsed by default",
            "help-keys: Space opens the help",
            "help-keys: Enter closes it",
            "requires: a row disabled by another setting shows the chip",
            "requires: the chip is a keyboard link",
            "requires: no lock line repeats the chip",
            "requires: a row that depends on its section is indented",
            "requires: Enter on the chip reveals and highlights the target",
            "requires: cross-page fixture applies",
            "requires: a chip can point to another page",
            "requires: a link to another page opens it and highlights the row",
            "requires: the accessible description says it once",
            "chips: at most 2 per row",
            "status-note: the Hyprland backend is reachable",
            "status-note: the note is translated",
            "status-note: no line without a note",
            "status-note: a paused row shows the translated note in italics",
            "status-note: the accessible description includes it",
            "status-note: the line goes away with Game Mode",
            "navigation: the count keeps the same width on every item",
            "navigation: pages with and without changes",
            "navigation: hidden at 0",
            "navigation: the count shows above 0 and is described",
            "navigation: no page title is elided",
            "navigation: a count appearing or a selection keeps the item's width",
            "navigation: the list is as wide as its longest title needs",
            "navigation: the window grew to 1600 px",
            "navigation: the list collapses at 760 px",
        ])
        titles = [e for e in events if e.get("type") == "nav-titles"]
        self.assertEqual([t["size"] for t in titles], ["1100x760", "1600x900", "760x720 expanded"])
        for report in titles:
            with self.subTest(size=report["size"]):
                self.assertTrue(report["titles"])
                self.assertEqual([t["title"] for t in report["titles"] if t["elided"] is not False], [])

    def test_unavailable_backend_shows_one_banner_and_no_fake_values(self) -> None:
        result, events, log = run_driver()
        self.assert_run(result, events, log, "backend-down", [
            "backend-down: one banner per section",
            "backend-down: rows show — instead of a value",
            "backend-down: rows do not repeat the banner's reason",
            "backend-down: Hyprland sections checked",
        ])
        checked = [c.get("page") for c in events if c.get("step") == "backend-down: Hyprland sections checked"]
        self.assertEqual(checked, ["windows", "input", "animations"])


if __name__ == "__main__":
    unittest.main()
