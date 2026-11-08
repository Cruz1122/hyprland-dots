"""Advanced > Diagnostics lists every backend the registry uses and its files.

The row says it shows where each kind of setting is saved and which parts can
be changed now, so a backend missing from AdvancedPage.qml (the animation
backend once was) hides its unavailable reason from that summary.
"""
from __future__ import annotations

import json
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SHELL = ROOT / "config/quickshell/ii"
PAGE = SHELL / "modules/settings/pages/AdvancedPage.qml"
REGISTRY = SHELL / "modules/settings/registry"
# Not a storage backend: read-only info rows, buttons and custom widgets.
NOT_STORAGE = {None, "readonly", "action"}


def block(text: str, name: str) -> str:
    match = re.search(r"readonly property var " + name + r": \[(.*?)\n\s*\]", text, re.S)
    if not match:
        raise AssertionError(f"diag.{name} not found in {PAGE}")
    return match.group(1)


class DiagnosticsListTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.text = PAGE.read_text(encoding="utf-8")

    def test_every_storage_backend_is_listed(self) -> None:
        used = set()
        for path in REGISTRY.glob("*.json"):
            for entry in json.loads(path.read_text(encoding="utf-8")).get("entries", []):
                used.add(entry.get("backend"))
        listed = re.findall(r'name: "(\w+)"', block(self.text, "backends"))
        self.assertEqual(len(listed), len(set(listed)), listed)
        self.assertEqual(set(listed), used - NOT_STORAGE)

    def test_animation_file_is_listed(self) -> None:
        paths = block(self.text, "paths")
        self.assertIn('{ label: Translation.tr("Animations"), value: `${diag.configDir}/hypr/custom/shell-animations.lua` }',
                      paths)
        # The same file AnimationBackend writes.
        backend = (SHELL / "modules/settings/backends/AnimationBackend.qml").read_text(encoding="utf-8")
        self.assertIn("`${root.configDir}/hypr/custom/shell-animations.lua`", backend)


if __name__ == "__main__":
    unittest.main()
