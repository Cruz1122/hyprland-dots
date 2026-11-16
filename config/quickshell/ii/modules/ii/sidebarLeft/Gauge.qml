import qs.modules.common
import qs.modules.common.widgets
import QtQuick

// Ring gauge of the system monitor: value in the middle, name and a detail
// line underneath.
Item {
    id: root
    required property string title
    // 0..1
    required property real value
    property string detail: ""
    property color accent: Appearance.colors.colPrimary
    readonly property bool critical: value >= 0.9
    readonly property color ink: critical ? Appearance.colors.colError : accent

    implicitWidth: 112
    implicitHeight: column.implicitHeight

    Column {
        id: column
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 6

        CircularProgress {
            id: ring
            anchors.horizontalCenter: parent.horizontalCenter
            implicitSize: 92
            lineWidth: 8
            gapAngle: 14
            value: Math.max(0, Math.min(1, root.value))
            colPrimary: root.ink
            colSecondary: Appearance.colors.colLayer2

            StyledText {
                anchors.centerIn: parent
                text: `${Math.round(root.value * 100)}`
                font.family: Appearance.font.family.numbers
                font.pixelSize: 26
                color: root.critical ? Appearance.colors.colError : Appearance.colors.colOnLayer1
            }
        }
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 6
            Rectangle { // Legend dot: same color as this resource's history line
                anchors.verticalCenter: parent.verticalCenter
                width: 8
                height: 8
                radius: 4
                color: root.accent
            }
            StyledText {
                text: root.title
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnLayer1
            }
        }
        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.detail
            font.family: Appearance.font.family.numbers
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }
    }
}
