from __future__ import annotations

import unittest
from pathlib import Path
import xml.etree.ElementTree as ET


ROOT = Path(__file__).resolve().parents[1]


class OpenCodeNotificationsContractTest(unittest.TestCase):
    def read(self, relative: str) -> str:
        return (ROOT / relative).read_text(encoding="utf-8")

    def test_mascot_assets_match_the_delta_readme_shape(self) -> None:
        for variant in ("dark", "light"):
            with self.subTest(variant=variant):
                path = ROOT / f"config/quickshell/ii/assets/opencode-delta-mascot-{variant}.svg"
                source = path.read_text(encoding="utf-8")
                svg = ET.fromstring(source)

                self.assertEqual(svg.tag.rsplit("}", 1)[-1], "svg")
                self.assertEqual(svg.attrib["viewBox"], "0 0 280 200")
                self.assertEqual(svg.attrib["shape-rendering"], "crispEdges")
                self.assertIn("Copyright (c) 2025 opencode", source)
                self.assertEqual(len(svg.findall(".//{*}rect")), 14)

    def test_classifier_covers_native_and_terminal_bridge_notifications(self) -> None:
        utils = self.read("config/quickshell/ii/modules/common/functions/NotificationUtils.qml")
        for message in (
            '"permission needs input"',
            '"question needs input"',
            '"session done"',
            '"session error"',
            '"session aborted"',
            '"model stopped responding"',
        ):
            self.assertIn(message, utils)
        self.assertIn('appName === "kitty"', utils)
        self.assertIn('appName.includes("opencode")', utils)

    def test_open_code_notifications_get_a_separate_mascot_group(self) -> None:
        notifications = self.read("config/quickshell/ii/services/Notifications.qml")
        self.assertIn("import qs.modules.common.functions", notifications)
        self.assertIn("NotificationUtils.isOpenCodeNotification(notif)", notifications)
        self.assertIn('groupKey: "app:opencode"', notifications)
        self.assertIn('displayName: "OpenCode"', notifications)
        self.assertIn("root.openCodeMascotIcon", notifications)

    def test_common_icon_widget_accepts_local_file_urls(self) -> None:
        icon = self.read("config/quickshell/ii/modules/common/widgets/NotificationAppIcon.qml")
        self.assertIn('source.startsWith("file:")', icon)
        self.assertIn("source: root.appIconSource", icon)


if __name__ == "__main__":
    unittest.main()
