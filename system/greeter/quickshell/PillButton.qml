import QtQuick

// Icon button for the corner pills. Shows its label as a tooltip-like caption
// while hovered.
Rectangle {
    id: root
    property string icon
    property string label
    signal clicked

    width: 44
    height: 44
    radius: height / 2
    color: area.containsMouse ? Theme.layer3 : "transparent"
    Behavior on color {
        ColorAnimation { duration: Theme.effectsDuration }
    }
    scale: area.pressed ? 0.9 : 1
    Behavior on scale {
        NumberAnimation { duration: Theme.fastSpatialDuration; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.fastSpatial }
    }

    Icon {
        anchors.centerIn: parent
        text: root.icon
        color: area.containsMouse ? Theme.ink : Theme.subtext
    }

    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.top
        anchors.bottomMargin: 12
        text: root.label
        color: Theme.subtext
        font.family: Theme.titleFont
        font.pixelSize: 12
        opacity: area.containsMouse ? 1 : 0
        Behavior on opacity {
            NumberAnimation { duration: Theme.effectsDuration }
        }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
