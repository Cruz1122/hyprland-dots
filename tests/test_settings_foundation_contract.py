from __future__ import annotations

import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (REPO_ROOT / path).read_text(encoding="utf-8")


class SettingsFoundationContractTest(unittest.TestCase):
    def test_settings_page_registers_foundation_page(self) -> None:
        settings_qml = read("config/quickshell/ii/settings.qml")
        self.assertIn("modules/settings/FoundationConfig.qml", settings_qml)
        self.assertIn("Translation.tr(\"Foundation\")", settings_qml)

    def test_settings_registry_declares_safe_config_backed_keys(self) -> None:
        registry_qml = read("config/quickshell/ii/services/SettingsRegistry.qml")
        for key in [
            "appearance.transparency.enable",
            "appearance.transparency.backgroundTransparency",
            "audio.protection.enable",
            "screenRecord.savePath",
            "screenRecord.fileFormat",
            "screenRecord.fps",
            "screenRecord.pixelFormat",
            "screenRecord.recordAudioByDefault",
            "screenRecord.fullscreenUsesFocusedMonitor",
        ]:
            self.assertIn(key, registry_qml)
        self.assertIn("readonly property int schemaVersion: 1", registry_qml)

    def test_settings_store_routes_writes_through_config_boundary(self) -> None:
        store_qml = read("config/quickshell/ii/services/SettingsStore.qml")
        self.assertIn("function setValue", store_qml)
        self.assertIn("Config.setNestedValue", store_qml)
        self.assertIn("operationFailed", store_qml)
        self.assertIn("operationSucceeded", store_qml)


if __name__ == "__main__":
    unittest.main()
