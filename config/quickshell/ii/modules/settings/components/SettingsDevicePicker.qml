import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.settings.components

ColumnLayout {
    id: root

    property string title: "Device"
    property string selectedName: ""
    property var devices: []
    property string emptyText: "No devices available"
    signal deviceSelected(string name)

    Layout.fillWidth: true
    spacing: SettingsMetrics.compactRowSpacing

    StyledText {
        Layout.fillWidth: true
        text: root.title
        color: Appearance.colors.colSubtext
        font.pixelSize: Appearance.font.pixelSize.small
    }

    StyledText {
        visible: root.devices.length === 0
        Layout.fillWidth: true
        text: root.emptyText
        color: Appearance.colors.colSubtext
        font.italic: true
    }

    Repeater {
        model: root.devices

        delegate: SettingsButton {
            required property var modelData
            property string deviceName: modelData.name || modelData.id || String(modelData)
            property string deviceLabel: modelData.description || modelData.nickname || deviceName

            label: deviceLabel
            materialIcon: "settings_input_component"
            toggled: root.selectedName === deviceName
            Layout.fillWidth: true
            onClicked: root.deviceSelected(deviceName)
        }
    }
}
