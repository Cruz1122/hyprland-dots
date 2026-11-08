import QtQuick
import qs.modules.common

// Keyboard focus outline drawn around `target` (a sibling or the parent).
Rectangle {
    id: root

    property Item target: parent
    property bool shown: false
    property real ringRadius: 12

    anchors.fill: root.target
    anchors.margins: -3
    radius: root.ringRadius + 3
    color: "transparent"
    border.width: 2
    border.color: Appearance.colors.colPrimary
    visible: root.shown
    z: 10
}
