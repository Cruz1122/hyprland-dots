import qs.modules.common
import QtQuick

// Divider between pinned and running apps.
Item {
    id: root
    property real lineHeight: 24
    implicitWidth: 9
    Rectangle {
        anchors.centerIn: parent
        width: 1
        height: root.lineHeight
        radius: 0.5
        color: Appearance.colors.colOutlineVariant
    }
}
