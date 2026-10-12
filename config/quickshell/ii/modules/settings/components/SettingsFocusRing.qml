import QtQuick
import qs.modules.common
import qs.modules.settings.components

Rectangle {
    id: root

    property Item target
    anchors.fill: root.target
    anchors.margins: -2
    radius: SettingsMetrics.controlRadius + 2
    color: "transparent"
    border.width: 2
    border.color: Appearance.colors.colPrimary
    visible: root.target && root.target.activeFocus
    z: 10
}
