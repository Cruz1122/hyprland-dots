"""How the Animations page registry is wired to its conditions (offline).

The `animationsLoaded` capability of AnimationBackend must gate every
animation row (cards, preset, curve library) and the [Apply Minimal] action:
without it, writes go to a file Hyprland never loads. Every capability with a
reason text in core/SettingsLogic.js CAPABILITY_REASONS must be used by some
enabledWhen, otherwise its text is dead (docs/settings.md, "Registry schema").
This contract check lives here, next to the Animations page, instead of in
tests/test_settings_contract.py.
"""
from __future__ import annotations

import json
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SETTINGS = ROOT / "config/quickshell/ii/modules/settings"
REGISTRY = SETTINGS / "registry"
LOGIC = SETTINGS / "core/SettingsLogic.js"
MASTER = {"key": "hyprland.animations.enabled", "equals": True}
LOADED = {"capability": "animationsLoaded"}


def leaves(cond: object) -> list[dict]:
    if not isinstance(cond, dict):
        return []
    out: list[dict] = []
    for name in ("all", "any"):
        for inner in cond.get(name, []):
            out += leaves(inner)
    if "not" in cond:
        out += leaves(cond["not"])
    if "capability" in cond or "key" in cond:
        out.append(cond)
    return out


def page(name: str) -> dict:
    return json.loads((REGISTRY / f"{name}.json").read_text(encoding="utf-8"))


class AnimationsWiringTest(unittest.TestCase):
    def setUp(self) -> None:
        self.doc = page("animations")
        self.entries = {e["key"]: e for e in self.doc["entries"]}

    def test_every_animation_row_needs_the_loaded_file(self) -> None:
        keys = [k for k, e in self.entries.items() if e.get("backend") == "animation"]
        self.assertEqual(len(keys), 12)
        for key in keys:
            with self.subTest(key=key):
                self.assertIn(LOADED, leaves(self.entries[key].get("enabledWhen")))
        # The cards and the preset still follow the master switch; the
        # curve library works with desktop animations off.
        for key in keys:
            if key != "animation.curves":
                with self.subTest(key=key):
                    self.assertEqual(self.entries[key]["enabledWhen"], {"all": [MASTER, LOADED]})
        self.assertEqual(self.entries["animation.curves"]["enabledWhen"], LOADED)

    def test_apply_minimal_needs_what_the_preset_needs(self) -> None:
        action = self.entries["action.animations.applyMinimal"]
        self.assertEqual(action["enabledWhen"], self.entries["animation.preset"]["enabledWhen"])
        # A check mark reads as "already applied" on this page.
        self.assertNotEqual(action.get("actionIcon"), "check")

    def test_shell_speed_waits_for_reduce_motion_off(self) -> None:
        order = [e["key"] for e in self.doc["entries"]]
        speed = self.entries["appearance.animations.durationScale"]
        self.assertEqual(speed["enabledWhen"], {"key": "appearance.animations.reduceMotion", "notEquals": True})
        # The dependent row comes right after the row it depends on.
        self.assertEqual(order.index("appearance.animations.durationScale"),
                         order.index("appearance.animations.reduceMotion") + 1)


class CapabilityReasonsContractTest(unittest.TestCase):
    def test_every_capability_reason_is_used(self) -> None:
        source = LOGIC.read_text(encoding="utf-8")
        block = re.search(r"var CAPABILITY_REASONS = \{(.*?)\};", source, re.S)
        self.assertIsNotNone(block)
        reasons = re.findall(r'"([^"]+)"\s*:', block.group(1))
        self.assertIn("animationsLoaded", reasons)
        used: set[str] = set()
        for path in sorted(REGISTRY.glob("*.json")):
            doc = json.loads(path.read_text(encoding="utf-8"))
            for entry in doc.get("entries", []) if isinstance(doc, dict) else []:
                used.update(c["capability"] for c in leaves(entry.get("enabledWhen")) if "capability" in c)
        self.assertEqual(sorted(set(reasons) - used), [])


if __name__ == "__main__":
    unittest.main()
