import qs.modules.common
import qs.modules.common.functions
import Qt5Compat.GraphicalEffects
import QtQuick
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.Notifications

// Themed icons load on the GUI thread (not `asynchronous`): with the KDE
// platform theme they come from KIconLoader, which is not thread-safe. Loaded
// from the image-loader thread it has crashed the shell and left the running
// shell unable to resolve icons that exist.
MaterialShape { // App icon
    id: root
    property var appIcon: ""
    property var summary: ""
    property var urgency: NotificationUrgency.Normal
    property bool isUrgent: urgency === NotificationUrgency.Critical
    property var image: ""
    property real materialIconScale: 0.57
    property real appIconScale: 0.8
    property real smallAppIconScale: 0.49
    property real materialIconSize: implicitSize * materialIconScale
    property real appIconSize: implicitSize * appIconScale
    property real smallAppIconSize: implicitSize * smallAppIconScale
    // `appIcon` is a monochrome mask to tint with the shape's ink color.
    property bool appIconIsMask: false
    // Icon of the app that relayed the notification (a terminal hosting a
    // TUI program), drawn as a small corner badge.
    property var badgeIcon: ""
    readonly property color inkColor: isUrgent ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSecondaryContainer
    // Icon name, absolute path or URL -> image source. Bare absolute paths
    // need the scheme, or they are looked up inside the application's qrc.
    function iconSource(icon) {
        const source = String(icon ?? "");
        if (source.startsWith("/"))
            return `file://${source}`;
        if (source.includes(":/"))
            return source;
        return Quickshell.iconPath(source, "image-missing");
    }
    readonly property string appIconSource: iconSource(root.appIcon)

    implicitSize: 38 * scale
    property list<var> urgentShapes: [
        MaterialShape.Shape.VerySunny,
        MaterialShape.Shape.SoftBurst,
    ]
    shape: isUrgent ? urgentShapes[Math.floor(Math.random() * urgentShapes.length)] : MaterialShape.Shape.Circle

    color: isUrgent ? Appearance.colors.colPrimaryContainer : Appearance.colors.colSecondaryContainer
    Loader {
        id: materialSymbolLoader
        active: root.appIcon == "" && root.image == ""
        anchors.fill: parent
        sourceComponent: MaterialSymbol {
            text: {
                const defaultIcon = NotificationUtils.findSuitableMaterialSymbol("")
                const guessedIcon = NotificationUtils.findSuitableMaterialSymbol(root.summary)
                return (root.urgency == NotificationUrgency.Critical && guessedIcon === defaultIcon) ?
                    "priority_high" : guessedIcon
            }
            anchors.fill: parent
            color: isUrgent ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSecondaryContainer
            iconSize: root.materialIconSize
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
    }
    Loader {
        id: maskIconLoader
        active: root.image == "" && root.appIcon != "" && root.appIconIsMask
        anchors.centerIn: parent
        sourceComponent: Item {
            implicitWidth: root.materialIconSize
            implicitHeight: root.materialIconSize
            Image {
                id: maskImage
                anchors.fill: parent
                visible: false
                asynchronous: true
                fillMode: Image.PreserveAspectFit
                sourceSize: Qt.size(width * 2, height * 2)
                source: root.appIconSource
            }
            ColorOverlay {
                anchors.fill: maskImage
                source: maskImage
                color: root.inkColor
            }
        }
    }
    Loader { // Relaying app, as a badge on the corner
        active: root.image == "" && root.badgeIcon != ""
        anchors {
            right: parent.right
            bottom: parent.bottom
            rightMargin: -3
            bottomMargin: -3
        }
        z: 1
        sourceComponent: Rectangle {
            implicitWidth: root.smallAppIconSize + 4
            implicitHeight: root.smallAppIconSize + 4
            radius: width / 2
            color: Appearance.colors.colLayer1
            IconImage {
                anchors.centerIn: parent
                implicitSize: root.smallAppIconSize
                    source: root.iconSource(root.badgeIcon)
            }
        }
    }
    Loader {
        id: appIconLoader
        active: root.image == "" && root.appIcon != "" && !root.appIconIsMask
        anchors.centerIn: parent
        sourceComponent: IconImage {
            id: appIconImage
            implicitSize: root.appIconSize
            source: root.appIconSource
        }
    }
    Loader {
        id: notifImageLoader
        active: root.image != ""
        anchors.fill: parent
        sourceComponent: Item {
            anchors.fill: parent
            StyledImage {
                id: notifImage
                anchors.fill: parent
                readonly property int size: parent.width

                source: root.image
                fillMode: Image.PreserveAspectCrop
                cache: false
                antialiasing: true
                asynchronous: true

                layer.enabled: true
                layer.effect: OpacityMask {
                    maskSource: Rectangle {
                        width: notifImage.size
                        height: notifImage.size
                        radius: Appearance.rounding.full
                    }
                }
            }
            Loader {
                id: notifImageAppIconLoader
                active: root.appIcon != ""
                anchors.bottom: parent.bottom
                anchors.right: parent.right
                sourceComponent: IconImage {
                    implicitSize: root.smallAppIconSize
                            source: root.appIconSource
                }
            }
        }
    }
}
