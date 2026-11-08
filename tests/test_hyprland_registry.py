"""Hyprland entries of the windows/input/animations/advanced registry agree with Hyprland 0.57.

Checked against tests/fixtures/hyprland-options.json (see FIXTURE_GENERATOR in
tests/test_hyprconfigurator.py), so no live session is needed.
"""
from __future__ import annotations

import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
REGISTRY = ROOT / "config/quickshell/ii/modules/settings/registry"
FIXTURE = ROOT / "tests/fixtures/hyprland-options.json"
# Registry type -> fixture types it may target. The fixture infers the type
# from the default, so floats with integral defaults appear as int.
COMPATIBLE = {"bool": {"bool"}, "int": {"int"}, "real": {"float", "int"}, "enum": {"int", "string"},
              "string": {"string"}, "list": {"string"}}
# CSS-like gaps ("5 5 5 5"): hl.config accepts an int for every side (verified
# with a no-op `hyprctl eval` on 0.57; a string fails with exit 7).
CSS_INT = {"general:gaps_in", "general:gaps_out"}


class HyprlandRegistryTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.fixture = json.loads(FIXTURE.read_text())
        cls.entries = [e for page in ("windows", "input", "animations", "advanced")
                       for e in json.loads((REGISTRY / f"{page}.json").read_text())["entries"]
                       if e.get("backend") == "hyprland"]

    def test_entries_exist(self) -> None:
        self.assertGreater(len(self.entries), 30)

    def test_entries_match_hyprland(self) -> None:
        for e in self.entries:
            with self.subTest(key=e["key"]):
                option = self.fixture[e["option"]]
                lua_path = e["option"].replace(":", ".").replace("-", "_")
                self.assertEqual(e["path"], lua_path)
                self.assertEqual(e["key"], "hyprland." + lua_path)
                if e["option"] in CSS_INT:
                    self.assertEqual(e["type"], "int")
                else:
                    self.assertIn(option["type"], COMPATIBLE[e["type"]])
                for bound in ("min", "max"):
                    if bound in e and option[bound] is not None:
                        self.assertGreaterEqual(e[bound], option["min"])
                        self.assertLessEqual(e[bound], option["max"])
                if e["type"] == "enum" and option["map"]:
                    allowed = {v for item in option["map"] for v in item.values()}
                    self.assertLessEqual({o["value"] for o in e["options"]}, allowed)

    def test_only_layout_entries_are_risky(self) -> None:
        risky = sorted(e["option"] for e in self.entries if e.get("risky"))
        self.assertEqual(risky, ["input:kb_layout", "input:kb_options", "input:kb_variant"])


if __name__ == "__main__":
    unittest.main()
