import qs.services
import qs.modules.common
import Qt5Compat.GraphicalEffects
import QtQuick
import Quickshell.Widgets

// Themed icons load on the GUI thread (not `asynchronous`): with the KDE
// platform theme they come from KIconLoader, which is not thread-safe. Loaded
// from the image-loader thread it has crashed the shell and left the running
// shell unable to resolve icons that exist.
// A window's icon, see WindowIcons. Size it with width/height.
Item {
    id: root
    property string windowClass: ""
    property string title: ""
    // The hosting terminal as a corner badge; too small to read on tiny icons.
    property bool showBadge: true
    readonly property var info: WindowIcons.describe(windowClass, title)

    IconImage {
        anchors.fill: parent
        visible: !root.info.isMask
        mipmap: true
        source: root.info.isMask ? "" : root.info.source
    }

    // Monochrome marks get a disc so they stay legible over any window.
    Rectangle {
        anchors.fill: parent
        visible: root.info.isMask
        radius: width / 2
        color: Appearance.colors.colSecondaryContainer

        Image {
            id: maskImage
            anchors.centerIn: parent
            width: parent.width * 0.6
            height: width
            visible: false
            asynchronous: true
            fillMode: Image.PreserveAspectFit
            // Fixed, so resizing the icon does not reload the image.
            sourceSize: Qt.size(128, 128)
            source: root.info.isMask ? root.info.source : ""
        }
        ColorOverlay {
            anchors.fill: maskImage
            source: maskImage
            color: Appearance.colors.colOnSecondaryContainer
        }
    }

    Rectangle {
        visible: root.showBadge && root.info.badge.length > 0
        anchors {
            right: parent.right
            bottom: parent.bottom
            rightMargin: -width * 0.15
            bottomMargin: -width * 0.15
        }
        width: Math.round(parent.width * 0.46)
        height: width
        radius: width / 2
        color: Appearance.colors.colLayer0

        IconImage {
            anchors.fill: parent
            anchors.margins: Math.max(1, parent.width * 0.12)
            mipmap: true
            source: root.info.badge
        }
    }
}
