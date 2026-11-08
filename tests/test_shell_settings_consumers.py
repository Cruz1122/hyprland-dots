"""Main-shell consumers keep the value type that Settings writes.

A numeric setting copied into a `property bool` turns every value above 0
into `true`, so a 0..1 slider only switches between "off" and "fully on"
(regionSelector.targetRegions.contentRegionOpacity did this). Generic over
every registry entry whose consumers bind the option to a typed property.
"""
from __future__ import annotations

import json
import re
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
SHELL = REPO / "config/quickshell/ii"
REGISTRY = SHELL / "modules/settings/registry"

# Declared QML types that keep each entry type's values intact.
KEEPS_VALUE = {
    "real": {"real", "double", "var"},
    "int": {"int", "real", "double", "var"},
}


def binding_pattern(path: str) -> re.Pattern[str]:
    """`property <type> <name>: Config.options.<path>` (optional chaining allowed), the whole path only."""
    dotted = r"\??\.".join(re.escape(part) for part in path.split("."))
    return re.compile(r"\bproperty\s+([\w<>]+)\s+\w+\s*:\s*Config\.options\??\." + dotted + r"(?![\w.?])")


def consumer_file(consumer: str) -> Path:
    return REPO / consumer if consumer.startswith("config/") else SHELL / consumer


def declarations(path: str, text: str) -> list[str]:
    return [match.group(1) for match in binding_pattern(path).finditer(text)]


def numeric_config_entries():
    for registry_file in sorted(REGISTRY.glob("*.json")):
        for entry in json.loads(registry_file.read_text(encoding="utf-8")).get("entries", []):
            if entry.get("backend") == "config" and entry.get("type") in KEEPS_VALUE:
                yield entry


class ScannerSelfTest(unittest.TestCase):
    def test_finds_typed_bindings_of_the_whole_path(self) -> None:
        text = "\n".join([
            "    property bool a: Config.options.regionSelector.targetRegions.contentRegionOpacity",
            "    property real b: Config.options?.regionSelector?.targetRegions?.contentRegionOpacity",
            "    property real c: Config.options.regionSelector.targetRegions.contentRegionOpacityExtra",
            "    property bool d: Config.options.regionSelector.targetRegions.contentRegionOpacity.enabled",
        ])
        self.assertEqual(declarations("regionSelector.targetRegions.contentRegionOpacity", text), ["bool", "real"])


class NumericConsumerTypes(unittest.TestCase):
    def test_numeric_settings_are_not_declared_bool_or_truncated(self) -> None:
        checked = 0
        for entry in numeric_config_entries():
            path = entry.get("path", entry["key"])
            for consumer in entry.get("consumers", []):
                file = consumer_file(consumer)
                if file.suffix != ".qml" or not file.is_file():
                    continue
                for declared in declarations(path, file.read_text(encoding="utf-8")):
                    checked += 1
                    with self.subTest(key=entry["key"], consumer=consumer):
                        self.assertIn(declared, KEEPS_VALUE[entry["type"]],
                                      f"{consumer} declares {entry['key']} ({entry['type']}) as `property {declared}`")
        # The scan must keep seeing the region selector opacities, or it proves nothing.
        self.assertGreaterEqual(checked, 2)

    def test_content_highlight_opacity_is_a_real(self) -> None:
        text = (SHELL / "modules/ii/regionSelector/RegionSelection.qml").read_text(encoding="utf-8")
        self.assertEqual(declarations("regionSelector.targetRegions.contentRegionOpacity", text), ["real"])


if __name__ == "__main__":
    unittest.main()
