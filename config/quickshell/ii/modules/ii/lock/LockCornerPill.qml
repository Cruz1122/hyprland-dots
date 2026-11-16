import QtQuick
import QtQuick.Layouts
import qs.modules.common

// Bordered pill holding a row of controls in a lock screen corner. Same look
// as the greeter's corner pills (system/greeter/quickshell/GreeterSurface.qml).
// A separate file: inline components fail to resolve on a live reload.
Rectangle {
    default property alias content: row.data
    implicitHeight: 52
    implicitWidth: row.implicitWidth + 16
    radius: height / 2
    color: Appearance.colors.colLayer1
    border.width: 1
    border.color: Appearance.colors.colOutlineVariant

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 2
    }
}
