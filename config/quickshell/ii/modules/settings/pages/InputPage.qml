import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs.modules.settings.core
import qs.modules.settings.components
import "../backends/HyprlandLogic.js" as HL

SettingsPage {
    id: inputPage
    pageId: "input"

    customDelegates: ({
        "hyprland.input.kb_layout": layoutPicker,
        "info.input.shortcuts": shortcutList
    })

    // Layout chips (the first is the default) plus a search over the xkb list.
    Component {
        id: layoutPicker

        ColumnLayout {
            id: picker
            property var row: null
            readonly property var selected: HL.toList(picker.row?.value)
            readonly property var known: (SettingsStore.revision, SettingsStore.choices("hyprland.input.kb_layout"))
            readonly property var matches: {
                const q = search.text.trim().toLowerCase();
                if (q.length === 0)
                    return [];
                return picker.known.filter(l => !picker.selected.includes(l.value)
                    && (l.value.toLowerCase().startsWith(q) || l.label.toLowerCase().includes(q))).slice(0, 8);
            }

            function labelOf(code) {
                return picker.known.find(l => l.value === code)?.label ?? code;
            }

            function setLayouts(list) {
                if (picker.row && list.length > 0)
                    picker.row.commit(list);
            }

            spacing: 10

            Flow {
                Layout.fillWidth: true
                spacing: 6

                Repeater {
                    model: picker.selected

                    delegate: Rectangle {
                        id: chip
                        required property string modelData
                        required property int index
                        implicitHeight: 32
                        implicitWidth: chipRow.implicitWidth + 20
                        radius: 8
                        color: chip.index === 0 ? Appearance.colors.colPrimaryContainer : Appearance.colors.colSecondaryContainer

                        RowLayout {
                            id: chipRow
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            anchors.leftMargin: 12
                            spacing: 2

                            StyledText {
                                text: chip.index === 0 ? Translation.tr("%1 (default)").arg(picker.labelOf(chip.modelData)) : picker.labelOf(chip.modelData)
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: chip.index === 0 ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSecondaryContainer
                            }

                            SettingsIconButton {
                                visible: chip.index > 0
                                size: 24
                                iconSize: 16
                                iconName: "arrow_upward"
                                iconColor: Appearance.colors.colOnSecondaryContainer
                                tooltip: Translation.tr("Make default")
                                onClicked: picker.setLayouts([chip.modelData].concat(picker.selected.filter(c => c !== chip.modelData)))
                            }

                            SettingsIconButton {
                                visible: picker.selected.length > 1
                                size: 24
                                iconSize: 16
                                iconName: "close"
                                iconColor: chip.index === 0 ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSecondaryContainer
                                tooltip: Translation.tr("Remove “%1”").arg(picker.labelOf(chip.modelData))
                                onClicked: picker.setLayouts(picker.selected.filter(c => c !== chip.modelData))
                            }
                        }
                    }
                }
            }

            SettingsTextField {
                id: search
                Layout.fillWidth: true
                enabled: picker.row?.rowEnabled ?? false
                placeholderText: Translation.tr("Add a layout: type its name or code")
                Accessible.name: Translation.tr("Add a layout")
                onAccepted: {
                    if (picker.matches.length > 0) {
                        picker.setLayouts(picker.selected.concat([picker.matches[0].value]));
                        search.text = "";
                    }
                }
            }

            Flow {
                Layout.fillWidth: true
                visible: picker.matches.length > 0
                spacing: 6

                Repeater {
                    model: picker.matches

                    delegate: SettingsButton {
                        required property var modelData
                        kind: "tonal"
                        iconName: "add"
                        text: `${modelData.label} (${modelData.value})`
                        onClicked: {
                            picker.setLayouts(picker.selected.concat([modelData.value]));
                            search.text = "";
                        }
                    }
                }
            }
        }
    }

    // Read-only list of `hyprctl -j binds` with a filter.
    Component {
        id: shortcutList

        ColumnLayout {
            id: shortcuts
            readonly property bool hyprland: (Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") ?? "").length > 0
            readonly property int limit: 60
            property var binds: []
            property string problem: shortcuts.hyprland ? "" : Translation.tr("Shortcuts can only be listed inside Hyprland.")
            readonly property var filtered: HL.filterBinds(shortcuts.binds, filter.text)

            spacing: 10

            Process {
                running: shortcuts.hyprland
                command: ["hyprctl", "-j", "binds"]
                stdout: StdioCollector {
                    id: bindsOut
                    onStreamFinished: {
                        try {
                            shortcuts.binds = HL.parseBinds(bindsOut.text, Translation.tr("Any key"));
                        } catch (error) {
                            console.warn(`[InputPage] cannot read hyprctl -j binds: ${error}`);
                            shortcuts.problem = Translation.tr("Could not read the shortcuts.");
                        }
                    }
                }
            }

            SettingsTextField {
                id: filter
                Layout.fillWidth: true
                visible: shortcuts.problem.length === 0
                placeholderText: Translation.tr("Search shortcuts")
                Accessible.name: Translation.tr("Search shortcuts")
            }

            StyledText {
                Layout.fillWidth: true
                visible: text.length > 0
                text: shortcuts.problem.length > 0 ? shortcuts.problem
                    : shortcuts.filtered.length === 0 && shortcuts.binds.length > 0 ? Translation.tr("No shortcuts match.")
                    : shortcuts.filtered.length > shortcuts.limit ? Translation.tr("Showing %1 of %2; refine the search to see more.").arg(shortcuts.limit).arg(shortcuts.filtered.length)
                    : ""
                wrapMode: Text.Wrap
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }

            Repeater {
                model: shortcuts.filtered.slice(0, shortcuts.limit)

                delegate: RowLayout {
                    id: bindRow
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 16

                    StyledText {
                        Layout.preferredWidth: 220
                        Layout.maximumWidth: 220
                        text: bindRow.modelData.keys
                        elide: Text.ElideRight
                        textFormat: Text.PlainText
                        font.family: Appearance.font.family.monospace
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colOnLayer1
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: bindRow.modelData.action
                        wrapMode: Text.Wrap
                        textFormat: Text.PlainText
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: bindRow.modelData.described ? Appearance.colors.colOnLayer1 : Appearance.colors.colSubtext
                    }
                }
            }
        }
    }
}
