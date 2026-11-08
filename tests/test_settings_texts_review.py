"""Texts fixed in the review wave stay true to the code and to the glossary.

- Advanced > Privacy on public networks: services/LauncherSearch.qml never
  hides a clipboard entry; it only blurs images listed next to a link with a
  keyword, so no text may promise hidden entries.
- Windows > Corner curve: rounding_power 1 is a straight diagonal corner, the
  least round shape, so the minimum caption cannot say "rounder".
- es_MX glossary: touchpad is «panel táctil»; the Advanced page says
  «interfaz», keeping «shell» only in the technical IPC row, which matches
  the IPC unavailable reasons («El shell principal ...»).
- Input > Active shortcuts: catch-all binds show a translated "Any key".
"""
from __future__ import annotations

import json
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SHELL = ROOT / "config/quickshell/ii"
REGISTRY = SHELL / "modules/settings/registry"
ES_MX = json.loads((SHELL / "translations/es_MX.json").read_text(encoding="utf-8"))
TEXT_FIELDS = ("label", "description", "help", "note", "minLabel", "maxLabel", "title")
# Technical row named like the IPC reasons; see the module docstring.
SHELL_ALLOWED = {"Main shell (IPC)"}


def registry(name: str) -> dict:
    return json.loads((REGISTRY / f"{name}.json").read_text(encoding="utf-8"))


def entry(page: dict, key: str) -> dict:
    found = [e for e in page["entries"] if e["key"] == key]
    assert len(found) == 1, key
    return found[0]


def texts(item: dict) -> list[str]:
    return [item[field] for field in TEXT_FIELDS if item.get(field)]


class WorkSafetyTextsTest(unittest.TestCase):
    def setUp(self) -> None:
        self.page = registry("advanced")

    def assert_says_blur(self, item: dict) -> None:
        for text in texts(item):
            with self.subTest(text):
                self.assertNotIn("clipboard entries", text.lower())
                self.assertIn(text, ES_MX)
                self.assertNotIn("entradas del portapapeles", ES_MX[text])
        joined = " ".join(texts(item))
        self.assertIn("blur", joined.lower())
        self.assertIn("desenfoc", " ".join(ES_MX[t] for t in texts(item)))

    def test_clipboard_switch_says_what_the_launcher_does(self) -> None:
        clipboard = entry(self.page, "workSafety.enable.clipboard")
        self.assertEqual(clipboard["consumers"], ["services/LauncherSearch.qml"])
        self.assert_says_blur(clipboard)
        self.assertIn("links stay visible", clipboard["help"])
        # The old label still finds the row.
        self.assertIn("Hide sensitive clipboard entries", clipboard["keywords"])

    def test_link_keywords_and_section_say_blur(self) -> None:
        self.assert_says_blur(entry(self.page, "workSafety.triggerCondition.linkKeywords"))
        section = [s for s in self.page["sections"] if s["id"] == "workSafety"][0]
        self.assert_says_blur(section)

    def test_launcher_still_only_blurs(self) -> None:
        # If LauncherSearch starts filtering entries, these texts need a new pass.
        code = (SHELL / "services/LauncherSearch.qml").read_text(encoding="utf-8")
        self.assertIn("blurImage: shouldBlurImage", code)
        self.assertIn("root.containsUnsafeLink(array[index - 1]) || root.containsUnsafeLink(array[index + 1])", code)


class RoundingPowerTextsTest(unittest.TestCase):
    def test_minimum_is_captioned_diagonal(self) -> None:
        power = entry(registry("windows"), "hyprland.decoration.rounding_power")
        self.assertEqual(power["min"], 1)
        self.assertEqual(power["minLabel"], "Diagonal")
        self.assertEqual(ES_MX["Diagonal"], "Diagonal")
        self.assertNotIn("redond", ES_MX[power["minLabel"]].lower())
        self.assertIn("1 cuts the corner diagonally", power["description"])
        self.assertIn("1 corta la esquina en diagonal", ES_MX[power["description"]])


class GlossaryTest(unittest.TestCase):
    def test_touchpad_is_panel_tactil(self) -> None:
        self.assertEqual([k for k, v in ES_MX.items() if "touchpad" in v.lower()], [])
        self.assertEqual(ES_MX["No touchpad detected"], "No se detectó ningún panel táctil")

    def test_advanced_page_says_interfaz(self) -> None:
        page = registry("advanced")
        strings = {t for item in page["sections"] + page["entries"] for t in texts(item)}
        strings.add(page["description"])
        qml = (SHELL / "modules/settings/pages/AdvancedPage.qml").read_text(encoding="utf-8")
        strings |= set(re.findall(r'Translation\.tr\("([^"]*)"\)', qml))
        self.assertIn("Reset every shell setting", strings)
        offenders = sorted(s for s in strings - SHELL_ALLOWED if "shell" in ES_MX.get(s, "").lower())
        self.assertEqual(offenders, [])
        for allowed in SHELL_ALLOWED:
            self.assertIn(allowed, strings)


class AnyKeyTest(unittest.TestCase):
    def test_input_page_translates_catch_all_binds(self) -> None:
        qml = (SHELL / "modules/settings/pages/InputPage.qml").read_text(encoding="utf-8")
        self.assertIn('HL.parseBinds(bindsOut.text, Translation.tr("Any key"))', qml)
        self.assertEqual(ES_MX["Any key"], "Cualquier tecla")


if __name__ == "__main__":
    unittest.main()
