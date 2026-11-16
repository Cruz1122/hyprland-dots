import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick

// Bar slider: the whole pill is the track, with the icon and the value inside.
Item {
    id: root
    required property string icon
    // 0..1; the owner applies `moved` and feeds the result back here.
    property real value: 0
    property string valueText: `${Math.round(value * 100)}%`
    // Optional tick (0..1), e.g. where the slider switches what it controls.
    property real mark: -1
    property color trackColor: Appearance.colors.colLayer1
    property color trackHoverColor: Appearance.colors.colLayer1Hover
    signal moved(real newValue)

    readonly property real shownValue: Math.max(0, Math.min(1, area.pressed ? area.dragValue : value))
    // The fill never gets narrower than a circle, so 0 still shows a knob.
    function fillWidth(fraction) {
        return height + (width - height) * fraction;
    }

    implicitHeight: 40

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: area.containsMouse ? root.trackHoverColor : root.trackColor
    }
    Rectangle {
        width: root.fillWidth(root.shownValue)
        height: parent.height
        radius: height / 2
        color: ColorUtils.mix(Appearance.colors.colPrimary, root.trackColor, area.pressed ? 0.44 : 0.34)
        Behavior on width {
            enabled: !area.pressed
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        Rectangle { // Grabber
            anchors {
                right: parent.right
                rightMargin: 9
                verticalCenter: parent.verticalCenter
            }
            width: 3
            height: 16
            radius: 1.5
            color: Appearance.colors.colPrimary
            opacity: area.containsMouse || area.pressed ? 0.9 : 0.5
        }
    }
    Rectangle {
        visible: root.mark >= 0
        x: root.fillWidth(root.mark) - 1
        anchors.verticalCenter: parent.verticalCenter
        width: 2
        height: 8
        radius: 1
        color: Appearance.colors.colSubtext
        opacity: 0.6
    }

    MaterialSymbol {
        anchors {
            left: parent.left
            leftMargin: 11
            verticalCenter: parent.verticalCenter
        }
        text: root.icon
        iconSize: 18
        color: Appearance.colors.colOnLayer1
    }
    StyledText {
        anchors {
            right: parent.right
            rightMargin: 14
            verticalCenter: parent.verticalCenter
        }
        text: root.valueText
        font.family: Appearance.font.family.numbers
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: Appearance.colors.colSubtext
    }

    MouseArea {
        id: area
        property real dragValue: 0
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        function update(mouseX) {
            dragValue = Math.max(0, Math.min(1, (mouseX - root.height / 2) / Math.max(1, root.width - root.height)));
            root.moved(dragValue);
        }
        onPressed: event => update(event.x)
        onPositionChanged: event => {
            if (pressed)
                update(event.x);
        }
        onWheel: event => root.moved(Math.max(0, Math.min(1, root.value + (event.angleDelta.y > 0 ? 0.02 : -0.02))))
    }
}
