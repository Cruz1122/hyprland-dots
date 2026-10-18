import QtQuick

// Shared by the real emblem/popup and the Qt pointer/animation tests. No I/O.
Item {
    id: root
    property bool active: true
    property bool pointerHovered: false
    property bool popupHovered: false
    property bool showing: false
    property int currentIndex: 0
    property int brandCount: 6
    property int rotationInterval: 6000
    property int closeDelay: 200
    property real imageOpacity: 1
    readonly property bool engaged: pointerHovered || popupHovered
    readonly property bool held: engaged || showing

    onEngagedChanged: {
        if (engaged && active) {
            closeTimer.stop();
            showing = true;
        } else {
            closeTimer.restart();
        }
    }
    onHeldChanged: {
        if (held) {
            transition.stop();
            imageOpacity = 1;
        }
    }
    onActiveChanged: {
        if (!active) {
            transition.stop();
            showing = false;
            imageOpacity = 1;
        } else if (engaged) {
            showing = true;
        }
    }

    Timer {
        id: closeTimer
        interval: root.closeDelay
        onTriggered: root.showing = false
    }
    Timer {
        interval: root.rotationInterval
        repeat: true
        running: root.active && !root.held
        onTriggered: transition.restart()
    }
    SequentialAnimation {
        id: transition
        NumberAnimation { target: root; property: "imageOpacity"; to: 0; duration: 140 }
        ScriptAction { script: root.currentIndex = (root.currentIndex + 1) % root.brandCount }
        NumberAnimation { target: root; property: "imageOpacity"; to: 1; duration: 180 }
    }
}
