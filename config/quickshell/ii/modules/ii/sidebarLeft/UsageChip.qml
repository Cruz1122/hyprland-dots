import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

// Small stat with a usage bar (swap, disk).
Rectangle {
    id: chip
    required property string icon
    required property string title
    required property real used
    required property real total
    Layout.fillWidth: true
    Layout.preferredWidth: 1
    implicitHeight: 58
    radius: Appearance.rounding.normal
    color: Appearance.colors.colLayer1

    MaterialSymbol {
        id: chipIcon
        anchors {
            left: parent.left
            leftMargin: 12
            top: parent.top
            topMargin: 10
        }
        text: chip.icon
        iconSize: 18
        color: Appearance.colors.colPrimary
    }
    StyledText {
        anchors {
            left: chipIcon.right
            leftMargin: 6
            verticalCenter: chipIcon.verticalCenter
        }
        text: chip.title
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: Appearance.colors.colOnLayer1
    }
    StyledText {
        anchors {
            right: parent.right
            rightMargin: 12
            verticalCenter: chipIcon.verticalCenter
        }
        text: `${chip.used.toFixed(chip.used < 10 ? 1 : 0)} / ${chip.total.toFixed(0)} GB`
        font.family: Appearance.font.family.numbers
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: Appearance.colors.colSubtext
    }
    Rectangle {
        id: track
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
            margins: 12
        }
        height: 4
        radius: 2
        color: Appearance.colors.colLayer2
        Rectangle {
            width: parent.width * Math.max(0, Math.min(1, chip.total > 0 ? chip.used / chip.total : 0))
            height: parent.height
            radius: 2
            color: Appearance.colors.colPrimary
            Behavior on width {
                animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
            }
        }
    }
}
