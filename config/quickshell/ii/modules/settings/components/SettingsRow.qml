import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs.modules.settings.core

// Base of every settings row: icon, label, description and state on the
// left, the control (default children) on the right, or below the text when
// the row is narrower than SettingsMetrics.rowStackWidth.
//
// Variants show SettingsStore values through Binding { restoreMode:
// Binding.RestoreNone } and call commit() only on user interaction. When
// commit() is rejected they receive rejected() and resync their control.
Item {
    id: row

    property string settingKey: ""
    // Entry as listed by the page (an alias copy carries aliasOf/homePageId).
    property var listedEntry: null
    readonly property var entry: SettingsRegistry.entry(row.settingKey)
    // Page rendering the row: provides actions, customDelegates and infoValues.
    property var page: null

    readonly property string label: Translation.tr(row.entry?.label ?? row.settingKey)
    readonly property string description: row.entry?.description ? Translation.tr(row.entry.description) : ""
    readonly property string note: row.entry?.note ? Translation.tr(row.entry.note) : ""
    readonly property string iconName: row.entry?.icon ?? ""
    readonly property bool writable: !!row.entry && row.entry.backend !== "action" && row.entry.backend !== "readonly" && row.entry.type !== "action" && row.entry.type !== "info"

    readonly property var value: (SettingsStore.revision, SettingsStore.value(row.settingKey))
    readonly property var defaultValue: (SettingsStore.revision, SettingsStore.defaultValue(row.settingKey))
    readonly property bool modified: row.writable && (SettingsStore.revision, SettingsStore.isModified(row.settingKey))
    readonly property bool rowEnabled: (SettingsStore.revision, SettingsStore.isEnabled(row.settingKey)) && row.extraEnabled
    // Variants may add their own requirement (for example a missing action handler).
    property bool extraEnabled: true
    property string extraDisabledReason: ""
    readonly property string disabledReason: row.rowEnabled ? "" : row.computeDisabledReason()

    property bool highlighted: false
    property bool busy: false
    property string errorText: ""
    readonly property bool hovered: hoverHandler.hovered

    // Forces the control below the text (text areas, lists, custom widgets).
    property bool stacked: false
    // In the stacked layout the control takes the whole width.
    property bool controlFillsWidth: false
    // Width of the control column in the side-by-side layout (-1: implicit).
    property real controlPreferredWidth: -1
    readonly property real availableWidth: row.width - 2 * SettingsMetrics.rowHorizontalPadding
    readonly property real controlWidthHint: row.controlPreferredWidth > 0 ? row.controlPreferredWidth : controlBox.implicitWidth
    readonly property bool compact: row.stacked || row.width < SettingsMetrics.rowStackWidth || row.controlWidthHint > row.availableWidth * 0.55
    // Set by variants from their control (visualFocus) to draw the focus ring.
    property bool focusVisible: false

    // Row click (outside the control). interactHandler performs the primary
    // interaction for the harness driver; both return false when unsupported.
    property var activateHandler: null
    property var interactHandler: null

    default property alias controlData: controlBox.data

    signal rejected()

    objectName: "row:" + row.settingKey
    implicitWidth: layout.implicitWidth + 2 * SettingsMetrics.rowHorizontalPadding
    implicitHeight: layout.implicitHeight + 2 * SettingsMetrics.rowVerticalPadding
    Accessible.name: row.label
    Accessible.description: row.description

    function computeDisabledReason() {
        if (row.extraDisabledReason.length > 0)
            return row.extraDisabledReason;
        if (!SettingsStore.isAvailable(row.settingKey))
            return Translation.tr(SettingsStore.unavailableReason(row.settingKey));
        const cond = SettingsStore.blockingCondition(row.settingKey);
        if (cond?.capability !== undefined)
            return Translation.tr("Not supported on this system");
        if (cond?.key !== undefined) {
            const other = SettingsRegistry.entry(cond.key);
            return Translation.tr("Depends on “%1”").arg(Translation.tr(other?.label ?? cond.key));
        }
        return Translation.tr("Not available");
    }

    function commit(newValue) {
        const ok = SettingsStore.write(row.settingKey, newValue);
        if (!ok)
            row.rejected();
        return ok;
    }

    function resetToDefault() {
        if (!SettingsStore.reset(row.settingKey))
            row.rejected();
    }

    function interact() {
        return row.rowEnabled && typeof row.interactHandler === "function" ? row.interactHandler() !== false : false;
    }

    function pulse() {
        row.highlighted = true;
        pulseAnimation.restart();
    }

    Connections {
        target: SettingsStore
        function onFailed(key, message) {
            if (key === row.settingKey)
                row.errorText = Translation.tr(message);
        }
        function onCommitted(key) {
            if (key === row.settingKey)
                row.errorText = "";
        }
    }

    HoverHandler {
        id: hoverHandler
    }

    // Clicks on the text or the empty part of the row; controls above it
    // receive their own clicks.
    MouseArea {
        anchors.fill: parent
        enabled: row.rowEnabled && typeof row.activateHandler === "function"
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: row.activateHandler()
    }

    Rectangle {
        id: background
        anchors.fill: parent
        radius: SettingsMetrics.rowRadius
        color: row.hovered && row.rowEnabled ? Appearance.colors.colLayer1Hover : "transparent"

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }
    }

    Rectangle {
        id: highlight
        anchors.fill: parent
        radius: SettingsMetrics.rowRadius
        color: Appearance.colors.colPrimaryContainer
        opacity: 0
        visible: opacity > 0
    }

    SequentialAnimation {
        id: pulseAnimation
        loops: 2
        NumberAnimation { target: highlight; property: "opacity"; to: 0.9; duration: 220; easing.type: Easing.OutCubic }
        NumberAnimation { target: highlight; property: "opacity"; to: 0.35; duration: 380; easing.type: Easing.InOutCubic }
        onFinished: fadeOut.start()
    }

    NumberAnimation {
        id: fadeOut
        target: highlight
        property: "opacity"
        to: 0
        duration: 900
        easing.type: Easing.InOutCubic
        onFinished: row.highlighted = false
    }

    SettingsFocusRing {
        target: background
        shown: row.focusVisible
        ringRadius: SettingsMetrics.rowRadius
    }

    GridLayout {
        id: layout
        anchors {
            left: parent.left
            right: parent.right
            verticalCenter: parent.verticalCenter
            leftMargin: SettingsMetrics.rowHorizontalPadding
            rightMargin: SettingsMetrics.rowHorizontalPadding
        }
        columns: row.compact ? 1 : 2
        columnSpacing: 20
        rowSpacing: 12

        RowLayout {
            id: textRow
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 14

            MaterialSymbol {
                id: leadingIcon
                visible: row.iconName.length > 0
                Layout.alignment: Qt.AlignTop
                Layout.topMargin: 1
                text: row.iconName
                iconSize: 22
                color: row.rowEnabled ? Appearance.colors.colOnSurfaceVariant : Appearance.colors.colOnLayer1Inactive
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                RowLayout {
                    id: labelRow
                    Layout.fillWidth: true
                    spacing: 8

                    // Capped at its natural width so the modified dot sits
                    // right after the text; wraps when the row is narrow.
                    StyledText {
                        id: labelText
                        Layout.fillWidth: true
                        Layout.maximumWidth: Math.ceil(labelMetrics.advanceWidth) + 1
                        text: row.label
                        wrapMode: Text.Wrap
                        font.pixelSize: Appearance.font.pixelSize.normal
                        color: row.rowEnabled ? Appearance.colors.colOnLayer1 : Appearance.colors.colOnLayer1Inactive
                    }

                    // Natural width of the label: a wrapped Text reports its
                    // wrapped width as implicitWidth, which would feed back.
                    TextMetrics {
                        id: labelMetrics
                        font: labelText.font
                        text: row.label
                    }

                    Rectangle {
                        visible: row.modified
                        Layout.alignment: Qt.AlignVCenter
                        implicitWidth: 8
                        implicitHeight: 8
                        radius: 4
                        color: Appearance.colors.colPrimary
                        Accessible.name: Translation.tr("Modified")
                    }

                    Item {
                        Layout.fillWidth: true
                    }
                }

                StyledText {
                    visible: text.length > 0
                    Layout.fillWidth: true
                    text: row.description
                    wrapMode: Text.Wrap
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }

                StyledText {
                    visible: text.length > 0
                    Layout.fillWidth: true
                    text: row.note
                    wrapMode: Text.Wrap
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.italic: true
                    color: Appearance.colors.colSubtext
                }

                StatusLine {
                    shown: row.disabledReason.length > 0
                    iconName: "lock"
                    text: row.disabledReason
                    color: Appearance.colors.colSubtext
                }

                StatusLine {
                    shown: row.errorText.length > 0
                    iconName: "error"
                    text: row.errorText
                    color: Appearance.colors.colError
                }

                StatusLine {
                    shown: !!row.listedEntry?.aliasOf && row.page?.pageId !== row.listedEntry?.homePageId
                    iconName: "link"
                    text: Translation.tr("Also in %1").arg(Translation.tr(SettingsRegistry.page(row.listedEntry?.homePageId ?? "")?.title ?? ""))
                    color: Appearance.colors.colSubtext
                }
            }
        }

        RowLayout {
            id: controlRow
            Layout.alignment: row.compact ? Qt.AlignLeft | Qt.AlignVCenter : Qt.AlignRight | Qt.AlignVCenter
            Layout.fillWidth: row.compact && row.controlFillsWidth
            Layout.preferredWidth: !row.compact && row.controlPreferredWidth > 0 ? row.controlPreferredWidth : -1
            Layout.leftMargin: row.compact && leadingIcon.visible ? leadingIcon.implicitWidth + textRow.spacing : 0
            spacing: 6

            SettingsIconButton {
                visible: row.modified && row.rowEnabled
                Layout.alignment: Qt.AlignVCenter
                iconName: "restart_alt"
                tooltip: Translation.tr("Reset to default")
                size: 32
                iconSize: 18
                onClicked: row.resetToDefault()
            }

            RowLayout {
                id: controlBox
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 8
                enabled: row.rowEnabled
                opacity: row.rowEnabled ? 1 : 0.5
            }
        }
    }

    component StatusLine: RowLayout {
        id: statusLine
        property bool shown: false
        property string iconName: ""
        property string text: ""
        property color color
        visible: statusLine.shown
        Layout.fillWidth: true
        Layout.topMargin: 2
        spacing: 6

        MaterialSymbol {
            Layout.alignment: Qt.AlignTop
            text: statusLine.iconName
            iconSize: 15
            color: statusLine.color
        }

        StyledText {
            Layout.fillWidth: true
            text: statusLine.text
            wrapMode: Text.Wrap
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: statusLine.color
        }
    }
}
