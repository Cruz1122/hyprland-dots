pragma ComponentBehavior: Bound
import QtQuick

// One shape per typed character, cycling like the lock screen's
// PasswordChars.qml, popping in on the shell's fast spatial curve. Scrolls so
// the latest character stays visible.
Item {
    id: root
    property int length: 0
    property color color: Theme.ink
    readonly property int charSize: 20

    clip: true

    Row {
        id: dots
        anchors.verticalCenter: parent.verticalCenter
        x: Math.min(0, root.width - width)
        Behavior on x {
            NumberAnimation { duration: Theme.fastSpatialDuration; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.fastSpatial }
        }

        Repeater {
            model: root.length
            delegate: Item {
                id: slot
                required property int index
                width: root.charSize
                height: root.charSize

                Rectangle {
                    id: shape
                    // circle, pill, diamond, rounded square
                    readonly property int kind: slot.index % 4
                    anchors.centerIn: parent
                    width: kind === 1 ? 16 : 12
                    height: kind === 1 ? 8 : 12
                    radius: kind === 0 || kind === 1 ? height / 2 : 3
                    rotation: kind === 2 ? 45 : 0
                    antialiasing: true
                    color: root.color
                    scale: 0.3
                    opacity: 0

                    Component.onCompleted: appear.start()
                    ParallelAnimation {
                        id: appear
                        NumberAnimation { target: shape; property: "scale"; to: 1; duration: Theme.fastSpatialDuration; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.fastSpatial }
                        NumberAnimation { target: shape; property: "opacity"; to: 1; duration: 80 }
                    }
                }
            }
        }
    }
}
