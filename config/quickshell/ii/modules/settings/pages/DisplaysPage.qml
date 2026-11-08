import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services
import qs.modules.settings.core
import qs.modules.settings.components
import "../backends/DisplayLogic.js" as DisplayLogic

// Displays and night light. Every layout change goes through
// SettingsStore.write("display.monitors", spec): the store previews it and
// asks to keep it, so a bad mode reverts by itself.
SettingsPage {
    id: displaysPage
    pageId: "displays"

    readonly property string monitorsKey: "display.monitors"
    readonly property var spec: (SettingsStore.revision, SettingsStore.value(displaysPage.monitorsKey)) ?? []
    readonly property var infos: (SettingsStore.revision, SettingsStore.choices(displaysPage.monitorsKey)) ?? []
    // Names only: cards are rebuilt when outputs come and go, not on every refresh.
    readonly property string monitorNames: displaysPage.spec.map(m => m.name).join("\n")

    // Explicit replacement of a hand-written monitors.lua: monitorsgen.py
    // --force backs it up next to itself first. DisplayBackend watches the
    // file and hides the action once it carries the marker.
    actions: ({
        replaceMonitors: entry => {
            if (displaysPage.spec.length === 0 || DisplayLogic.validate(displaysPage.spec).length > 0)
                return;
            Quickshell.execDetached(DisplayLogic.generatorArgs(Quickshell.shellPath("scripts/settings/monitorsgen.py"),
                DisplayLogic.outputPath(FileUtils.trimFileProtocol(Directories.home)), displaysPage.spec, "write", true));
        }
    })

    customDelegates: ({
        "display.monitors": monitorCards,
        "display.presets": presetButtons
    })

    function info(name) {
        return displaysPage.infos.find(m => m.name === name) ?? null;
    }

    function monitor(name) {
        return displaysPage.spec.find(m => m.name === name) ?? null;
    }

    function commit(row, next) {
        if (next === null) {
            row.rejected();
            return false;
        }
        return row.commit(next);
    }

    function arrangementLabel(value) {
        if (value === "auto")
            return Translation.tr("Automatic");
        if (value === "custom")
            return Translation.tr("Custom position");
        const parts = value.split(":");
        const other = parts.slice(1).join(":");
        switch (parts[0]) {
        case "right": return Translation.tr("Right of %1").arg(other);
        case "left": return Translation.tr("Left of %1").arg(other);
        case "above": return Translation.tr("Above %1").arg(other);
        case "below": return Translation.tr("Below %1").arg(other);
        case "mirror": return Translation.tr("Duplicate %1").arg(other);
        }
        return value;
    }

    Component {
        id: presetButtons

        Flow {
            id: presets
            property var row: null
            readonly property var available: DisplayLogic.availablePresets(displaysPage.spec)
            readonly property var labels: ({
                extend: { text: Translation.tr("Extend"), icon: "splitscreen_right" },
                mirror: { text: Translation.tr("Duplicate"), icon: "flip" },
                internal: { text: Translation.tr("Built-in only"), icon: "laptop" },
                external: { text: Translation.tr("External only"), icon: "desktop_windows" }
            })
            Layout.fillWidth: true
            spacing: 8

            Repeater {
                model: presets.available
                delegate: SettingsButton {
                    required property string modelData
                    enabled: presets.row?.rowEnabled ?? false
                    iconName: presets.labels[modelData].icon
                    text: presets.labels[modelData].text
                    onClicked: {
                        const next = DisplayLogic.preset(displaysPage.spec, displaysPage.infos, modelData);
                        if (next !== null)
                            SettingsStore.write(displaysPage.monitorsKey, next);
                    }
                }
            }
        }
    }

    Component {
        id: monitorCards

        ColumnLayout {
            id: cards
            property var row: null
            Layout.fillWidth: true
            spacing: 10

            Repeater {
                model: displaysPage.monitorNames.length > 0 ? displaysPage.monitorNames.split("\n") : []
                delegate: MonitorCard {
                    required property string modelData
                    Layout.fillWidth: true
                    name: modelData
                    row: cards.row
                }
            }
        }
    }

    component MonitorCard: Rectangle {
        id: card
        property string name: ""
        property var row: null
        readonly property var monitor: displaysPage.monitor(card.name)
        readonly property var info: displaysPage.info(card.name)
        readonly property bool enabledOutput: card.monitor?.enabled ?? false
        readonly property bool lastEnabled: card.enabledOutput && DisplayLogic.enabledCount(displaysPage.spec) <= 1
        readonly property bool interactive: card.row?.rowEnabled ?? false
        readonly property var size: card.monitor ? DisplayLogic.modeSize(card.monitor, card.info) : ({ width: 0, height: 0 })
        readonly property string arrangementValue: DisplayLogic.arrangement(displaysPage.spec, displaysPage.infos, card.name)
        readonly property bool vrrCapable: card.info?.hardwareDetails?.vrrCapable === true || (card.monitor?.vrr ?? 0) !== 0
        readonly property bool wide: card.width >= 600

        function change(field, value) {
            displaysPage.commit(card.row, DisplayLogic.setField(displaysPage.spec, card.name, field, value));
        }

        implicitHeight: cardLayout.implicitHeight + 28
        radius: SettingsMetrics.cardRadius
        color: Appearance.colors.colLayer2

        ColumnLayout {
            id: cardLayout
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: 14
            }
            spacing: 12

            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                MaterialSymbol {
                    text: DisplayLogic.isInternal(card.name) ? "laptop" : "desktop_windows"
                    iconSize: 24
                    color: card.enabledOutput ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    StyledText {
                        Layout.fillWidth: true
                        text: card.name
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.normal
                        color: Appearance.colors.colOnLayer2
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: {
                            const parts = [];
                            if (card.info?.description)
                                parts.push(card.info.description);
                            if (!card.enabledOutput)
                                parts.push(Translation.tr("Off"));
                            else if (card.monitor?.mirror)
                                parts.push(Translation.tr("Duplicating %1").arg(card.monitor.mirror));
                            return parts.join(" · ");
                        }
                        visible: text.length > 0
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }
                }

                StyledSwitch {
                    id: enabledSwitch
                    enabled: card.interactive && !card.lastEnabled
                    Accessible.name: Translation.tr("Use %1").arg(card.name)
                    onToggled: card.change("enabled", enabledSwitch.checked)

                    Binding {
                        target: enabledSwitch
                        property: "checked"
                        value: card.enabledOutput
                        restoreMode: Binding.RestoreNone
                    }
                    Connections {
                        target: card.row
                        function onRejected() { enabledSwitch.checked = card.enabledOutput; }
                    }
                }
            }

            GridLayout {
                visible: card.enabledOutput
                Layout.fillWidth: true
                columns: card.wide ? 2 : 1
                columnSpacing: 16
                rowSpacing: 10

                MonitorField {
                    label: Translation.tr("Resolution")
                    row: card.row
                    enabled: card.interactive
                    options: DisplayLogic.modeChoices(card.info, card.monitor?.mode).map(o => ({
                        value: o.value,
                        label: o.translate === false ? o.label : Translation.tr(o.label)
                    }))
                    currentValue: card.monitor?.mode ?? "preferred"
                    onPicked: value => card.change("mode", value)
                }

                MonitorField {
                    label: Translation.tr("Scale")
                    row: card.row
                    enabled: card.interactive
                    options: DisplayLogic.scaleChoices(card.size.width, card.size.height, card.monitor?.scale)
                    currentValue: card.monitor?.scale ?? 1
                    onPicked: value => card.change("scale", value)
                }

                MonitorField {
                    label: Translation.tr("Rotation")
                    row: card.row
                    enabled: card.interactive
                    options: DisplayLogic.TRANSFORMS.map(o => ({ value: o.value, label: Translation.tr(o.label) }))
                    currentValue: card.monitor?.transform ?? 0
                    onPicked: value => card.change("transform", value)
                }

                MonitorField {
                    visible: displaysPage.spec.length > 1
                    label: Translation.tr("Position")
                    row: card.row
                    enabled: card.interactive
                    options: DisplayLogic.arrangementChoices(displaysPage.spec, card.name, card.arrangementValue).map(v => ({
                        value: v,
                        label: displaysPage.arrangementLabel(v)
                    }))
                    currentValue: card.arrangementValue
                    onPicked: value => displaysPage.commit(card.row, DisplayLogic.applyArrangement(displaysPage.spec, displaysPage.infos, card.name, value))
                }

                MonitorField {
                    visible: card.vrrCapable
                    label: Translation.tr("Variable refresh rate")
                    row: card.row
                    enabled: card.interactive
                    options: DisplayLogic.VRR_MODES.map(o => ({ value: o.value, label: Translation.tr(o.label) }))
                    currentValue: card.monitor?.vrr ?? null
                    onPicked: value => card.change("vrr", value)
                }
            }
        }
    }

    // Label above a drop-down; writes only on activation and resyncs when
    // the store rejects the change.
    component MonitorField: ColumnLayout {
        id: field
        property string label: ""
        property var options: []
        property var currentValue: null
        property var row: null
        readonly property int currentIndex: field.options.findIndex(o => o.value === field.currentValue)
        signal picked(var value)

        Layout.fillWidth: true
        // Equal preferred widths make the grid split its columns evenly.
        Layout.preferredWidth: 1
        spacing: 4

        StyledText {
            Layout.fillWidth: true
            text: field.label
            elide: Text.ElideRight
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }

        StyledComboBox {
            id: combo
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            enabled: field.enabled
            model: field.options
            textRole: "label"
            Accessible.name: field.label
            onActivated: index => {
                const option = field.options[index];
                if (option && option.value !== field.currentValue)
                    field.picked(option.value);
            }
        }

        Binding {
            target: combo
            property: "currentIndex"
            value: field.currentIndex
            restoreMode: Binding.RestoreNone
        }

        Connections {
            target: field.row
            function onRejected() { combo.currentIndex = field.currentIndex; }
        }
    }
}
