from __future__ import annotations

import os
from pathlib import Path
import shutil
import subprocess
import unittest
import xml.etree.ElementTree as ET


ROOT = Path(__file__).resolve().parents[1]
BAR = ROOT / "config/quickshell/ii/modules/ii/bar"
ASSETS = ROOT / "config/quickshell/ii/assets/icons/ai"
QT_TEST_RUNNER = shutil.which("qmltestrunner6") or next(
    (str(path) for path in (
        Path("/usr/lib/qt6/bin/qmltestrunner"),
        Path("/usr/lib64/qt6/bin/qmltestrunner"),
    ) if path.is_file()), None,
)


class ResourcePresentationTests(unittest.TestCase):
    @unittest.skipUnless(QT_TEST_RUNNER, "Qt 6 Quick Test is not installed")
    def test_behavior_with_qt_javascript_engine(self) -> None:
        assert QT_TEST_RUNNER is not None
        environment = {
            **os.environ,
            "QT_QUICK_BACKEND": "software",
            "QML2_IMPORT_PATH": str(ROOT / "config/quickshell/ii"),
            "QML_IMPORT_PATH": str(ROOT / "config/quickshell/ii"),
            "QML_XHR_ALLOW_FILE_READ": "1",
        }
        for filename in (
            "tst_AiEmblemState.qml",
            "tst_AiQuotaPresentation.qml",
            "tst_ResourcePresentation.qml",
        ):
            with self.subTest(filename=filename):
                result = subprocess.run(
                    [QT_TEST_RUNNER, "-input", str(ROOT / "tests/qml" / filename), "-platform", "offscreen"],
                    capture_output=True, text=True, timeout=60, env=environment,
                )
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_resource_layout_keeps_full_popup_and_two_pills(self) -> None:
        source = (BAR / "Resources.qml").read_text()
        self.assertEqual(source.count("ResourcePill {"), 2)
        self.assertIn("AiEmblem {", source)
        self.assertIn("ResourcesPopup {", source)
        self.assertIn("hoverTarget: resourceHoverTarget", source)
        self.assertNotIn("Resource {", source)

    def test_all_six_emblems_are_local_svg_symbols(self) -> None:
        source = (BAR / "AiEmblem.qml").read_text()
        for brand in ("openai", "opencode", "antigravity", "zed", "cursor", "claude"):
            self.assertIn(f'file: "{brand}"', source)
            svg = ET.parse(ASSETS / f"{brand}.svg").getroot()
            self.assertTrue(svg.attrib.get("viewBox"))
            self.assertIsNotNone(svg.find("{http://www.w3.org/2000/svg}path"))
        state = (BAR / "AiEmblemState.qml").read_text()
        self.assertIn("property int rotationInterval: 6000", state)
        self.assertIn("running: root.active && !root.held", state)
        # The emblem now intentionally opens the AI quota panel on left click.
        self.assertIn("GlobalStates.openAiQuotaPanel", source)
        self.assertNotIn('file: "anthropic"', source)
        self.assertIn("readonly property real emblemSize: 16", source)
        self.assertIn("width: root.emblemSize *", source)

    def test_resource_labels_have_no_percent_suffix(self) -> None:
        source = (BAR / "ResourcePill.qml").read_text()
        self.assertIn('text: root.resource ? Math.round(root.resource.value * 100) : "--"', source)
        self.assertIn("iconSize: Appearance.font.pixelSize.smaller + 2", source)
        self.assertIn("implicitHeight: 18", source)

    def test_opencode_keeps_its_hollow_monochrome_shape(self) -> None:
        svg = ET.parse(ASSETS / "opencode.svg").getroot()
        paths = svg.findall("{http://www.w3.org/2000/svg}path")
        self.assertEqual(len(paths), 1)
        self.assertEqual(svg.attrib["fill-rule"], "evenodd")
        self.assertEqual(paths[0].attrib["d"], "M16 6H8v12h8V6zm4 16H4V2h16v20z")

    def test_battery_foreground_is_shared_and_state_aware(self) -> None:
        source = (BAR / "BatteryIndicator.qml").read_text()
        self.assertIn("chargingIndicator ?", source)
        self.assertIn("isLow ? Appearance.m3colors.m3error", source)
        self.assertIn(
            'color: chargingIndicator ? "#4A3900" : Appearance.colors.colOnSecondaryContainer',
            source,
        )
        self.assertEqual(source.count("color: Appearance.colors.colOnSecondaryContainer"), 1)


if __name__ == "__main__":
    unittest.main()
