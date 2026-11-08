"""Texts of the Animations page that must stay true to the code (offline).

- The bounce curve names follow how far each dotfiles curve overshoots.
- The Minimal preset is not described as motion-free: it keeps slides.
- The reduce-motion help points to the master switch by its label.
"""
from __future__ import annotations

import json
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SETTINGS = ROOT / "config/quickshell/ii/modules/settings"
LOGIC_JS = SETTINGS / "backends/AnimationLogic.js"
REGISTRY = SETTINGS / "registry/animations.json"
BASE = json.loads((ROOT / "tests/fixtures/hyprbase-sample.json").read_text(encoding="utf-8"))
ES_MX = json.loads((ROOT / "config/quickshell/ii/translations/es_MX.json").read_text(encoding="utf-8"))


def peak_y(points: list[float]) -> float:
    """Highest y of a CSS-style cubic bezier from (0, 0) to (1, 1)."""
    _, y1, _, y2 = points
    best = 0.0
    for i in range(10001):
        t = i / 10000
        u = 1 - t
        best = max(best, 3 * u * u * t * y1 + 3 * u * t * t * y2 + t ** 3)
    return best


def js_object(name: str) -> dict[str, str]:
    text = LOGIC_JS.read_text(encoding="utf-8")
    block = re.search(rf"var {name} = \{{(.*?)\n\}};", text, re.S)
    assert block is not None, name
    return dict(re.findall(r'"?([A-Za-z_]+)"?\s*:\s*"([^"]*)"', block.group(1)))


class AnimationTextsTest(unittest.TestCase):
    def test_bounce_names_follow_the_overshoot(self) -> None:
        labels = js_object("CURVE_LABELS")
        bounces = sorted((name for name, label in labels.items() if label.endswith(" bounce")),
                         key=lambda name: peak_y(BASE["curves"][name]["points"]))
        self.assertEqual([labels[name] for name in bounces], ["Light bounce", "Medium bounce", "Strong bounce"],
                         {name: round(peak_y(BASE["curves"][name]["points"]), 4) for name in bounces})

    def test_minimal_is_not_described_as_motion_free(self) -> None:
        description = js_object("PRESET_DESCRIPTIONS")["minimal"]
        for text in (description, ES_MX[description]):
            with self.subTest(text=text):
                self.assertNotRegex(text.lower(), r"almost no movement|casi sin movimiento|without moving|sin moverse")
        self.assertRegex(description, r"still move")

    def test_reduce_motion_points_to_the_master_switch(self) -> None:
        entries = {e["key"]: e for e in json.loads(REGISTRY.read_text(encoding="utf-8"))["entries"]}
        label = entries["hyprland.animations.enabled"]["label"]
        help_text = entries["appearance.animations.reduceMotion"]["help"]
        self.assertIn(f"“{label}”", help_text)
        self.assertIn(f"«{ES_MX[label]}»", ES_MX[help_text])


if __name__ == "__main__":
    unittest.main()
