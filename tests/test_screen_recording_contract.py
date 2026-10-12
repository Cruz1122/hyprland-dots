from __future__ import annotations

import json
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (REPO_ROOT / path).read_text(encoding="utf-8")


class ScreenRecordingContractTest(unittest.TestCase):
    def test_settings_page_registers_screen_recording_page(self) -> None:
        settings_qml = read("config/quickshell/ii/settings.qml")
        self.assertIn("modules/settings/ScreenRecordingConfig.qml", settings_qml)
        self.assertIn("Translation.tr(\"Screen Recording\")", settings_qml)

    def test_config_declares_screen_recording_defaults(self) -> None:
        config_qml = read("config/quickshell/ii/modules/common/Config.qml")
        for expected in [
            "property string fileFormat: \"mp4\"",
            "property int fps: 60",
            "property string pixelFormat: \"yuv420p\"",
            "property bool recordAudioByDefault: true",
            "property bool fullscreenUsesFocusedMonitor: true",
            "property string barButtonAction: \"fullscreen\"",
            "property string audioSource: \"system\"",
            "property string micDevice: \"\"",
            "property string systemAudioDevice: \"\"",
        ]:
            self.assertIn(expected, config_qml)

    def test_repo_config_contains_screen_recording_values_with_expected_types(self) -> None:
        data = json.loads((REPO_ROOT / "config/illogical-impulse/config.json").read_text(encoding="utf-8"))
        screen_record = data["screenRecord"]
        self.assertIsInstance(screen_record["savePath"], str)
        self.assertIn(screen_record["fileFormat"], ["mp4", "mkv", "webm"])
        self.assertIsInstance(screen_record["fps"], int)
        self.assertGreaterEqual(screen_record["fps"], 1)
        self.assertLessEqual(screen_record["fps"], 240)
        self.assertIn(screen_record["pixelFormat"], ["yuv420p", "nv12", "auto"])
        self.assertIsInstance(screen_record["recordAudioByDefault"], bool)
        self.assertIsInstance(screen_record["fullscreenUsesFocusedMonitor"], bool)
        self.assertIn(screen_record["barButtonAction"], ["fullscreen", "region", "pause", "stop"])
        self.assertIsInstance(screen_record.get("micDevice", ""), str)
        self.assertIsInstance(screen_record.get("systemAudioDevice", ""), str)

    def test_record_script_reads_new_options_and_keeps_legacy_flags(self) -> None:
        script = read("config/quickshell/ii/scripts/videos/record.sh")
        for expected in [
            ".screenRecord.fileFormat",
            ".screenRecord.fps",
            ".screenRecord.pixelFormat",
            ".screenRecord.fullscreenUsesFocusedMonitor",
            "--region",
            "--sound",
            "--fullscreen",
            "--pause",
            "--stop",
            "--framerate",
            "wf-recorder.pid",
        ]:
            self.assertIn(expected, script)

    def test_overlay_fullscreen_button_uses_default_audio_setting(self) -> None:
        recorder_qml = read("config/quickshell/ii/modules/ii/overlay/recorder/Recorder.qml")
        self.assertIn("recordAudioByDefault", recorder_qml)
        self.assertIn("command.push(\"--sound\")", recorder_qml)

    def test_overlay_region_button_uses_default_audio_setting(self) -> None:
        recorder_qml = read("config/quickshell/ii/modules/ii/overlay/recorder/Recorder.qml")
        self.assertIn("recordAudioByDefault ? \"recordWithSound\" : \"record\"", recorder_qml)
        self.assertIn("ipc", recorder_qml)

    def test_sidebar_record_button_uses_default_audio_setting(self) -> None:
        util_buttons_qml = read("config/quickshell/ii/modules/ii/sidebarLeft/SidebarLeftContent.qml")
        self.assertIn("recordAudioByDefault", util_buttons_qml)
        self.assertIn("barButtonAction", util_buttons_qml)
        self.assertIn("command.push(\"--sound\")", util_buttons_qml)
        self.assertNotIn("[Directories.recordScriptPath, \"--fullscreen\", \"--sound\"]", util_buttons_qml)
        self.assertIn('title: Translation.tr("Screen record")', util_buttons_qml)

    def test_screen_recording_page_exposes_actions_and_bar_customization(self) -> None:
        page_qml = read("config/quickshell/ii/modules/settings/ScreenRecordingConfig.qml")
        for expected in [
            "Record screen",
            "Record region",
            "Pause / Resume",
            "Stop",
            "Bar button",
            "screenRecord.barButtonAction",
        ]:
            self.assertIn(expected, page_qml)
        self.assertNotIn("title: Translation.tr(\"Status\")", page_qml)

    def test_registry_declares_bar_button_action_enum(self) -> None:
        registry_qml = read("config/quickshell/ii/services/SettingsRegistry.qml")
        self.assertIn("screenRecord.barButtonAction", registry_qml)
        self.assertIn("options: [\"fullscreen\", \"region\", \"pause\", \"stop\"]", registry_qml)


if __name__ == "__main__":
    unittest.main()
