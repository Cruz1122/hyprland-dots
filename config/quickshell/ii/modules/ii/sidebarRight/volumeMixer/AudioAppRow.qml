import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.sidebarRight.controls
import qs.services
import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

// One application stream on the audio page: icon and name over its volume bar.
// Clicking the icon mutes it.
Rectangle {
    id: root
    required property PwNode node
    readonly property bool muted: node?.audio?.muted ?? false

    PwObjectTracker {
        objects: [root.node]
    }

    implicitHeight: 88
    radius: Appearance.rounding.normal
    color: Appearance.colors.colLayer1

    MouseArea {
        id: iconArea
        anchors {
            left: parent.left
            leftMargin: 12
            top: parent.top
            topMargin: 10
        }
        width: 24
        height: 24
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.node.audio.muted = !root.muted

        StyledImage {
            anchors.fill: parent
            opacity: root.muted ? 0.35 : 1
            source: {
                let icon = AppSearch.guessIcon(root.node?.properties["application.icon-name"] ?? "");
                if (!AppSearch.iconExists(icon))
                    icon = AppSearch.guessIcon(root.node?.properties["node.name"] ?? "");
                return Quickshell.iconPath(icon, "image-missing");
            }
        }
        StyledToolTip {
            text: root.muted ? Translation.tr("Click to unmute") : Translation.tr("Click to mute")
        }
    }
    StyledText {
        anchors {
            left: iconArea.right
            leftMargin: 10
            right: parent.right
            rightMargin: 12
            verticalCenter: iconArea.verticalCenter
        }
        elide: Text.ElideRight
        textFormat: Text.PlainText
        text: {
            // application.name -> description -> name
            const app = Audio.appNodeDisplayName(root.node);
            const media = root.node?.properties["media.name"];
            return media != undefined ? `${app}  ·  ${media}` : app;
        }
        font.pixelSize: Appearance.font.pixelSize.small
        color: root.muted ? Appearance.colors.colSubtext : Appearance.colors.colOnLayer1
    }

    ControlSlider {
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
            margins: 8
        }
        implicitHeight: 34
        trackColor: Appearance.colors.colLayer2
        trackHoverColor: Appearance.colors.colLayer2Hover
        icon: root.muted ? (root.node?.isSink ? "volume_off" : "mic_off") : (root.node?.isSink ? "volume_up" : "mic")
        value: root.node?.audio?.volume ?? 0
        onMoved: newValue => root.node.audio.volume = newValue
    }
}
