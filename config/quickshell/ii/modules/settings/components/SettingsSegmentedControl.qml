import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.settings.components

Flow {
    id: root

    property list<var> options: []
    property var currentValue
    signal selected(var value)
    Layout.fillWidth: true
    spacing: 4

    Repeater {
        model: root.options

        delegate: SettingsButton {
            required property var modelData
            required property int index
            label: modelData.displayName || modelData.label || String(modelData.value)
            materialIcon: modelData.icon || ""
            toggled: root.currentValue == modelData.value
            Accessible.name: label
            onClicked: root.selected(modelData.value)
        }
    }
}
