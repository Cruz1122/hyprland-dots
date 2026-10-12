import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.settings.components

ApplicationWindow {
    visible: false
    width: 900
    height: 700
    title: "Settings components gallery"
    color: Appearance.m3colors.m3background

    SettingsPage {
        anchors.fill: parent
        title: "Settings components"

        SettingsPageHeader {
            title: "Component gallery"
            description: "Temporary visual harness for the states used by the settings migration."
        }

        SettingsSection {
            title: "Interactive controls"
            icon: "tune"

            SettingsSwitchRow {
                title: "Enabled setting"
                description: "Hover, focus, disabled and selected states are exercised here."
                icon: "toggle_on"
                checked: true
            }

            SettingsNumberRow {
                title: "Numeric setting"
                from: 0
                to: 100
                value: 42
            }

            SettingsSliderRow {
                title: "Slider setting"
                from: 0
                to: 100
                value: 60
            }

            SettingsSegmentedControl {
                currentValue: "one"
                options: [
                    { displayName: "One", value: "one" },
                    { displayName: "Two", value: "two" },
                    { displayName: "Three", value: "three" }
                ]
            }

            SettingsDevicePicker {
                title: "Audio device"
                devices: [
                    { name: "default", description: "Default device" },
                    { name: "secondary", description: "Secondary device" }
                ]
                selectedName: "default"
            }
        }

        SettingsSection {
            title: "Feedback and text"
            icon: "feedback"

            SettingsSubsection {
                title: "Text inputs"
                description: "Help text is exposed through the help button."

                SettingsTextField {
                    label: "Short text"
                    placeholderText: "Type something"
                }

                SettingsTextArea {
                    label: "Long text"
                    placeholderText: "Long content, translations and error states"
                }
            }

            SettingsBanner {
                text: "Informational banner with a visible action area."
                SettingsButton {
                    label: "Action"
                }
            }
        }
    }
}
