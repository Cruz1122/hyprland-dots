import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs.modules.settings.core

// Notice inside a section card. As a registry row (widget "banner") it shows
// the entry's icon, label and description; SettingsSection also uses it
// without a key for the section's "unavailable" notice (`text` only).
Item {
    id: row

    property string settingKey: ""
    property var listedEntry: null
    property var page: null
    readonly property var entry: row.settingKey.length > 0 ? SettingsRegistry.entry(row.settingKey) : null
    property string title: row.entry ? Translation.tr(row.entry.label) : ""
    property string text: row.entry?.description ? Translation.tr(row.entry.description) : ""
    property string iconName: row.entry?.icon || "info"
    property bool highlighted: false

    objectName: row.settingKey.length > 0 ? "row:" + row.settingKey : "banner"
    implicitWidth: layout.implicitWidth + 2 * SettingsMetrics.rowHorizontalPadding
    implicitHeight: layout.implicitHeight + 2 * SettingsMetrics.rowVerticalPadding
    Accessible.role: Accessible.StaticText
    Accessible.name: row.title.length > 0 ? row.title : row.text
    Accessible.description: row.title.length > 0 ? row.text : ""

    // Banners have nothing to change (harness interaction contract).
    function interact() {
        return false;
    }

    function pulse() {
        row.highlighted = true;
        pulseAnimation.restart();
    }

    Rectangle {
        anchors.fill: parent
        radius: SettingsMetrics.rowRadius
        color: Appearance.colors.colSecondaryContainer
    }

    Rectangle {
        id: highlight
        anchors.fill: parent
        radius: SettingsMetrics.rowRadius
        color: Appearance.colors.colPrimaryContainer
        opacity: 0
        visible: opacity > 0
    }

    // Same search highlight pulse as SettingsRow.
    SequentialAnimation {
        id: pulseAnimation
        loops: 2
        NumberAnimation { target: highlight; property: "opacity"; to: 0.9; duration: 220; easing.type: Easing.OutCubic } // motion-ok: search highlight pulse
        NumberAnimation { target: highlight; property: "opacity"; to: 0.35; duration: 380; easing.type: Easing.InOutCubic } // motion-ok: search highlight pulse
        onFinished: fadeOut.start()
    }

    NumberAnimation {
        id: fadeOut
        target: highlight
        property: "opacity"
        to: 0
        duration: 900 // motion-ok: search highlight pulse
        easing.type: Easing.InOutCubic
        onFinished: row.highlighted = false
    }

    RowLayout {
        id: layout
        anchors {
            left: parent.left
            right: parent.right
            verticalCenter: parent.verticalCenter
            leftMargin: SettingsMetrics.rowHorizontalPadding
            rightMargin: SettingsMetrics.rowHorizontalPadding
        }
        spacing: 14

        MaterialSymbol {
            Layout.alignment: Qt.AlignTop
            text: row.iconName
            iconSize: 22
            color: Appearance.colors.colOnSecondaryContainer
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            StyledText {
                visible: text.length > 0
                Layout.fillWidth: true
                text: row.title
                wrapMode: Text.Wrap
                font.weight: Font.Medium
                color: Appearance.colors.colOnSecondaryContainer
            }

            StyledText {
                visible: text.length > 0
                Layout.fillWidth: true
                text: row.text
                wrapMode: Text.Wrap
                font.pixelSize: row.title.length > 0 ? Appearance.font.pixelSize.smaller : Appearance.font.pixelSize.small
                color: Appearance.colors.colOnSecondaryContainer
            }
        }
    }
}
