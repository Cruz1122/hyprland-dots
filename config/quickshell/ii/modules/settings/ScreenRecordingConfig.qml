import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import Quickshell.Services.Pipewire
import qs.modules.settings.components

SettingsPage {
    forceWidth: true

    SettingsSection {
        icon: "screen_record"
        title: Translation.tr("Screen recording")

        SettingsBanner {
            Layout.fillWidth: true
            materialIcon: "info"
            text: Translation.tr("These options are read by the wf-recorder script.")
        }

        SettingsSubsection {
            title: Translation.tr("Actions")
            tooltip: Translation.tr("Use these controls to start, pause/resume, or stop the current recording.")

            Flow {
                Layout.fillWidth: true
                spacing: 8

                SettingsActionButton {
                    materialIcon: "screen_record"
                    label: Translation.tr("Record screen")
                    onClicked: startFullscreenRecording()
                }

                SettingsActionButton {
                    materialIcon: "screenshot_region"
                    label: Translation.tr("Record region")
                    onClicked: startRegionRecording()
                }

                SettingsActionButton {
                    materialIcon: "pause"
                    label: Translation.tr("Pause / Resume")
                    onClicked: Quickshell.execDetached([Directories.recordScriptPath, "--pause"])
                }

                SettingsActionButton {
                    materialIcon: "stop_circle"
                    label: Translation.tr("Stop")
                    onClicked: Quickshell.execDetached([Directories.recordScriptPath, "--stop"])
                }
            }
        }

        SettingsSubsection {
            title: Translation.tr("Output")

            SettingsTextArea {
                Layout.fillWidth: true
                placeholderText: Translation.tr("Recording save path")
                text: Config.options.screenRecord.savePath ?? ""
                wrapMode: TextEdit.Wrap
                onTextChanged: Config.options.screenRecord.savePath = text
            }

            SettingsNumberRow {
                icon: "speed"
                text: Translation.tr("Frames per second")
                from: 1
                to: 240
                stepSize: 1
                value: Config.options.screenRecord.fps ?? 60
                onValueChanged: Config.options.screenRecord.fps = value
            }
        }

        SettingsSubsection {
            title: Translation.tr("Format")

            SettingsSegmentedControl {
                currentValue: Config.options.screenRecord.fileFormat ?? "mp4"
                onSelected: newValue => Config.options.screenRecord.fileFormat = newValue
                options: [
                    { value: "mp4", displayName: "MP4" },
                    { value: "mkv", displayName: "MKV" },
                    { value: "webm", displayName: "WebM" }
                ]
            }

            SettingsSegmentedControl {
                currentValue: Config.options.screenRecord.pixelFormat ?? "yuv420p"
                onSelected: newValue => Config.options.screenRecord.pixelFormat = newValue
                options: [
                    { value: "yuv420p", displayName: "yuv420p" },
                    { value: "nv12", displayName: "nv12" },
                    { value: "auto", displayName: Translation.tr("Auto") }
                ]
            }
        }

        SettingsSubsection {
            title: Translation.tr("Behavior")

            SettingsSwitchRow {
                buttonIcon: "brand_awareness"
                text: Translation.tr("Record audio by default")
                checked: Config.options.screenRecord.recordAudioByDefault ?? true
                onCheckedChanged: Config.options.screenRecord.recordAudioByDefault = checked
            }

            SettingsSegmentedControl {
                currentValue: Config.options.screenRecord.audioSource ?? "system"
                onSelected: newValue => Config.options.screenRecord.audioSource = newValue
                options: [
                    { value: "system", displayName: Translation.tr("System audio") },
                    { value: "mic", displayName: Translation.tr("Microphone") },
                    { value: "both", displayName: Translation.tr("System + microphone") },
                    { value: "none", displayName: Translation.tr("No audio") }
                ]
            }

            Loader {
                Layout.fillWidth: true
                active: Config.options.screenRecord.audioSource === "mic" || Config.options.screenRecord.audioSource === "both"
                sourceComponent: SettingsDevicePicker {
                    title: Translation.tr("Microphone device")
                    devices: Audio.inputDevices
                    selectedName: Config.options.screenRecord.micDevice
                    onDeviceSelected: Config.options.screenRecord.micDevice = name
                }
            }

            Loader {
                Layout.fillWidth: true
                active: Config.options.screenRecord.audioSource === "system" || Config.options.screenRecord.audioSource === "both"
                sourceComponent: SettingsDevicePicker {
                    title: Translation.tr("System audio device")
                    devices: Audio.outputDevices
                    selectedName: Config.options.screenRecord.systemAudioDevice
                    onDeviceSelected: Config.options.screenRecord.systemAudioDevice = name
                }
            }

            SettingsSwitchRow {
                buttonIcon: "select_window"
                text: Translation.tr("Fullscreen uses focused monitor")
                checked: Config.options.screenRecord.fullscreenUsesFocusedMonitor ?? true
                onCheckedChanged: Config.options.screenRecord.fullscreenUsesFocusedMonitor = checked
            }
        }
    }

    SettingsSection {
        icon: "dock_to_right"
        title: Translation.tr("Bar button")

        SettingsBanner {
            Layout.fillWidth: true
            materialIcon: "touch_app"
            text: Translation.tr("Choose what the recording button in the bar does.")
        }

        SettingsSegmentedControl {
            currentValue: Config.options.screenRecord.barButtonAction ?? "fullscreen"
            onSelected: newValue => Config.options.screenRecord.barButtonAction = newValue
            options: [
                { value: "fullscreen", displayName: Translation.tr("Record screen") },
                { value: "region", displayName: Translation.tr("Record region") },
                { value: "pause", displayName: Translation.tr("Pause / Resume") },
                { value: "stop", displayName: Translation.tr("Stop") }
            ]
        }
    }

    function startFullscreenRecording() {
        const command = [Directories.recordScriptPath, "--fullscreen"];
        if (Config.options.screenRecord.recordAudioByDefault ?? true) {
            const src = Config.options.screenRecord.audioSource ?? "system";
            if (src === "system") command.push("--sound");
            else if (src === "mic") command.push("--mic");
            else if (src === "both") { command.push("--sound"); command.push("--mic"); }
        }
        Quickshell.execDetached(command);
    }

    function startRegionRecording() {
        const action = (Config.options.screenRecord.recordAudioByDefault ?? true) ? "recordWithSound" : "record";
        Quickshell.execDetached(["qs", "-p", Quickshell.shellPath(""), "ipc", "call", "region", action]);
    }

}
