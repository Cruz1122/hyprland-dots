from __future__ import annotations

import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (REPO_ROOT / path).read_text(encoding="utf-8")


class DisplayControlContractTest(unittest.TestCase):
    def test_display_control_is_global_and_has_minimal_actions(self) -> None:
        shell = read("config/quickshell/ii/shell.qml")
        panel = read("config/quickshell/ii/modules/common/displayControl/DisplayControl.qml")
        self.assertIn("DisplayControl {}", shell)
        for action in ["mirror", "laptop", "external", "reset"]:
            self.assertIn(f'action: "{action}"', panel)
        self.assertNotIn('action: "extend"', panel)
        self.assertIn('name: "displayControlToggle"', panel)

    def test_super_p_is_display_control_and_pin_has_compatibility_binding(self) -> None:
        keybinds = read("config/hypr/hyprland/keybinds.lua")
        self.assertIn('hl.bind("SUPER + P", hl.dsp.global("quickshell:displayControlToggle")', keybinds)
        self.assertIn('hl.bind("SUPER + ALT + P", hl.dsp.window.pin()', keybinds)
        self.assertNotIn('hl.bind("SUPER + P", hl.dsp.window.pin()', keybinds)

    def test_display_control_uses_lua_monitor_api_and_runtime_restore(self) -> None:
        panel = read("config/quickshell/ii/modules/common/displayControl/DisplayControl.qml")
        monitor_data = read("config/quickshell/ii/services/HyprlandData.qml")
        self.assertIn('["hyprctl", "eval"', panel)
        self.assertIn("hl.monitor(", panel)
        self.assertIn('["hyprctl", "reload"]', panel)
        self.assertIn('const source = laptop ??', panel)
        self.assertIn('const targetMode = target.availableModes?.find', panel)
        self.assertIn('No compatible mirror resolution', panel)
        self.assertIn('monitorRule(target, false, source.name, targetMode, "1")', panel)
        self.assertIn('const enabledRules = []', panel)
        self.assertIn('rules = enabledRules.concat(disabledRules)', panel)
        self.assertIn('hl.dispatch(hl.dsp.focus({ monitor = ${quoteLua(target.name)} }))', panel)
        self.assertIn('commandProc.command = root.pendingCommand', panel)
        self.assertIn('color: "#1c1c1c"', panel)
        self.assertIn('property var allMonitors: []', monitor_data)
        self.assertIn('["hyprctl", "monitors", "all", "-j"]', monitor_data)

    def test_audio_devices_are_deduplicated_by_pipewire_node_name(self) -> None:
        audio = read("config/quickshell/ii/services/Audio.qml")
        self.assertIn("const unique = []", audio)
        self.assertIn("existing.name === node.name", audio)
        self.assertIn("const preferred = isSink ? Pipewire.defaultAudioSink : Pipewire.defaultAudioSource", audio)
        self.assertIn("unique[duplicateIndex] = node", audio)

    def test_audio_selectors_expose_auto_mode(self) -> None:
        audio = read("config/quickshell/ii/services/Audio.qml")
        waffle = read("config/quickshell/ii/modules/waffle/actionCenter/volumeControl/VolumeControl.qml")
        mixer = read("config/quickshell/ii/modules/ii/sidebarRight/volumeMixer/VolumeDialogContent.qml")
        self.assertIn("function setAutoSink()", audio)
        self.assertIn("function setAutoSource()", audio)
        self.assertIn('Translation.tr("Auto")', waffle)
        self.assertIn('Translation.tr("Auto")', mixer)
        self.assertIn("Pipewire.preferredDefaultAudioSink = null", audio)
        self.assertIn("root.outputAuto = Pipewire.preferredDefaultAudioSink === null", audio)


if __name__ == "__main__":
    unittest.main()
