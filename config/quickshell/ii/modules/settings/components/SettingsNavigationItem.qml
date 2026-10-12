import QtQuick
import QtQuick.Layouts
import qs.modules.settings.components

SettingsButton {
    id: root

    required property var page
    required property int pageIndex
    property bool expanded: true
    property bool selected: false
    signal pageSelected(int index)

    label: root.expanded ? root.page.name : ""
    materialIcon: root.page.icon || "settings"
    iconRotation: root.page.iconRotation || 0
    toggled: root.selected
    Layout.fillWidth: true
    Accessible.name: root.page.name

    onClicked: root.pageSelected(root.pageIndex)
}
