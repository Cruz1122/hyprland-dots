import QtQuick
import QtQuick.Layouts
import qs.modules.settings.components

RowLayout {
    id: root

    property list<var> tabs: []
    property int currentIndex: 0
    signal tabSelected(int index)
    spacing: 4

    Repeater {
        model: root.tabs

        delegate: SettingsTabButton {
            required property var modelData
            required property int index
            label: modelData.label || modelData.displayName || String(index + 1)
            materialIcon: modelData.icon || ""
            selected: root.currentIndex === index
            Layout.fillWidth: true
            onClicked: root.tabSelected(index)
        }
    }
}
