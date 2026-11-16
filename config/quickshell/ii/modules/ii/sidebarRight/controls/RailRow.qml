import qs.modules.common
import qs.modules.common.widgets
import QtQuick

// List row of a rail page: icon bubble, title, subtitle and trailing actions
// (default children, right-aligned).
Rectangle {
    id: root
    property string icon: ""
    // Fills the bubble with the accent: the current network, a connected device.
    property bool highlighted: false
    property string title: ""
    property string subtitle: ""
    property bool interactive: false
    readonly property bool hovered: hover.hovered
    default property alias trailing: trailingRow.data
    signal clicked()

    implicitHeight: 56
    radius: Appearance.rounding.normal
    color: interactive && area.containsPress ? Appearance.colors.colLayer1Active
        : hovered ? Appearance.colors.colLayer1Hover : Appearance.colors.colLayer1
    Behavior on color {
        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
    }

    HoverHandler {
        id: hover
    }
    MouseArea {
        id: area
        anchors.fill: parent
        enabled: root.interactive
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }

    Rectangle {
        id: bubble
        anchors {
            left: parent.left
            leftMargin: 10
            verticalCenter: parent.verticalCenter
        }
        width: 36
        height: 36
        radius: 18
        color: root.highlighted ? Appearance.colors.colPrimary : Appearance.colors.colLayer2
        MaterialSymbol {
            anchors.centerIn: parent
            text: root.icon
            iconSize: 20
            fill: root.highlighted ? 1 : 0
            color: root.highlighted ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1
        }
    }
    Column {
        anchors {
            left: bubble.right
            leftMargin: 10
            right: trailingRow.left
            rightMargin: 8
            verticalCenter: parent.verticalCenter
        }
        StyledText {
            width: parent.width
            elide: Text.ElideRight
            text: root.title
            textFormat: Text.PlainText
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colOnLayer1
        }
        StyledText {
            width: parent.width
            visible: text.length > 0
            elide: Text.ElideRight
            text: root.subtitle
            textFormat: Text.PlainText
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }
    }
    Row {
        id: trailingRow
        anchors {
            right: parent.right
            rightMargin: 10
            verticalCenter: parent.verticalCenter
        }
        spacing: 6
    }
}
