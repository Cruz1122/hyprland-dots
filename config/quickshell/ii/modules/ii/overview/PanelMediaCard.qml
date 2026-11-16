pragma ComponentBehavior: Bound
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

// "Now playing" card for the launcher panel. With no media player it shows
// system load instead of an empty card.
Rectangle {
    id: root
    // Position polling and art downloads only run while the panel is shown.
    property bool live: true
    readonly property MprisPlayer player: MprisController.activePlayer
    readonly property bool hasPlayer: player !== null
    readonly property string artUrl: player?.trackArtUrl ?? ""
    readonly property string artFilePath: artUrl.length > 0 ? `${Directories.coverArt}/${Qt.md5(artUrl)}` : ""
    property string displayedArt: ""
    readonly property real progress: (player && player.length > 0) ? Math.max(0, Math.min(1, player.position / player.length)) : 0

    radius: Appearance.rounding.normal
    color: Appearance.colors.colLayer1

    onArtFilePathChanged: {
        root.displayedArt = "";
        if (artFilePath.length === 0)
            return;
        // Bindings are not re-read by a running Process: set, then start.
        artDownloader.command = ["bash", "-c", '[ -f "$1" ] || curl -4 -sSL --max-time 10 "$2" -o "$1"', "_", artFilePath, artUrl];
        artDownloader.requestedPath = artFilePath;
        artDownloader.running = true;
    }

    Process {
        id: artDownloader
        property string requestedPath: ""
        onExited: exitCode => {
            // Ignore a download that finished after the track changed again.
            if (exitCode === 0 && requestedPath === root.artFilePath)
                root.displayedArt = Qt.resolvedUrl(requestedPath);
        }
    }

    Timer { // MPRIS does not push position updates
        running: root.live && root.player?.playbackState === MprisPlaybackState.Playing
        interval: 1000
        repeat: true
        onTriggered: root.player.positionChanged()
    }

    component ControlButton: Rectangle {
        id: button
        property string icon
        property bool prominent: false
        signal clicked
        implicitWidth: prominent ? 40 : 32
        implicitHeight: implicitWidth
        radius: width / 2
        opacity: enabled ? 1 : 0.35
        color: prominent ? (buttonArea.containsMouse ? Appearance.colors.colPrimaryHover : Appearance.colors.colPrimary)
            : (buttonArea.containsMouse ? Appearance.colors.colLayer2Hover : "transparent")
        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }
        MaterialSymbol {
            anchors.centerIn: parent
            text: button.icon
            fill: 1
            iconSize: button.prominent ? Appearance.font.pixelSize.huge : Appearance.font.pixelSize.larger
            color: button.prominent ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1
        }
        MouseArea {
            id: buttonArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: button.clicked()
        }
    }

    component LoadRow: RowLayout {
        id: loadRow
        property string icon
        property string label
        property real value: 0
        spacing: 8
        MaterialSymbol {
            text: loadRow.icon
            fill: 1
            iconSize: Appearance.font.pixelSize.larger
            color: Appearance.colors.colSubtext
        }
        StyledText {
            text: loadRow.label
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colOnLayer1
            Layout.preferredWidth: 34
        }
        Rectangle {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            implicitHeight: 4
            radius: 2
            color: Appearance.colors.colLayer2
            Rectangle {
                width: parent.width * Math.max(0, Math.min(1, loadRow.value))
                height: parent.height
                radius: 2
                color: Appearance.colors.colPrimary
            }
        }
        StyledText {
            text: `${Math.round(loadRow.value * 100)}%`
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
            horizontalAlignment: Text.AlignRight
            Layout.preferredWidth: 34
        }
    }

    ColumnLayout { // Now playing
        visible: root.hasPlayer
        anchors {
            fill: parent
            margins: 12
        }
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Rectangle { // Cover art
                id: artFrame
                implicitWidth: 56
                implicitHeight: 56
                radius: Appearance.rounding.small
                color: Appearance.colors.colLayer2
                MaterialSymbol {
                    anchors.centerIn: parent
                    visible: artImage.status !== Image.Ready
                    text: "music_note"
                    fill: 1
                    iconSize: Appearance.font.pixelSize.hugeass
                    color: Appearance.colors.colSubtext
                }
                Image {
                    id: artImage
                    anchors.fill: parent
                    source: root.displayedArt
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: false
                    sourceSize.width: 112
                    sourceSize.height: 112
                    layer.enabled: true
                    layer.effect: OpacityMask {
                        maskSource: Rectangle {
                            width: artFrame.width
                            height: artFrame.height
                            radius: artFrame.radius
                        }
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                StyledText {
                    Layout.fillWidth: true
                    text: StringUtils.cleanMusicTitle(root.player?.trackTitle) || Translation.tr("No media")
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer1
                    elide: Text.ElideRight
                    maximumLineCount: 2
                    wrapMode: Text.Wrap
                }
                StyledText {
                    Layout.fillWidth: true
                    text: root.player?.trackArtist ?? ""
                    visible: text.length > 0
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    elide: Text.ElideRight
                }
            }
        }

        Item { Layout.fillHeight: true }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            StyledText {
                text: StringUtils.friendlyTimeForSeconds(root.player?.position)
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colSubtext
            }
            Rectangle {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                implicitHeight: 4
                radius: 2
                color: Appearance.colors.colLayer2
                Rectangle {
                    width: parent.width * root.progress
                    height: parent.height
                    radius: 2
                    color: Appearance.colors.colPrimary
                }
            }
            StyledText {
                text: StringUtils.friendlyTimeForSeconds(root.player?.length)
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colSubtext
            }
        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 14
            ControlButton {
                icon: "skip_previous"
                enabled: root.player?.canGoPrevious ?? false
                onClicked: root.player.previous()
            }
            ControlButton {
                prominent: true
                icon: root.player?.isPlaying ? "pause" : "play_arrow"
                enabled: root.player?.canTogglePlaying ?? false
                onClicked: root.player.togglePlaying()
            }
            ControlButton {
                icon: "skip_next"
                enabled: root.player?.canGoNext ?? false
                onClicked: root.player.next()
            }
        }
    }

    ColumnLayout { // No player: system load
        visible: !root.hasPlayer
        anchors {
            fill: parent
            margins: 14
        }
        spacing: 10
        StyledText {
            text: Translation.tr("System")
            font.pixelSize: Appearance.font.pixelSize.small
            font.weight: Font.DemiBold
            color: Appearance.colors.colOnLayer1
        }
        LoadRow {
            Layout.fillWidth: true
            icon: "planner_review"
            label: "CPU"
            value: ResourceUsage.cpuUsage
        }
        LoadRow {
            Layout.fillWidth: true
            icon: "memory"
            label: "RAM"
            value: ResourceUsage.memoryUsedPercentage
        }
        LoadRow {
            Layout.fillWidth: true
            visible: ResourceUsage.gpuAvailable
            icon: "developer_board"
            label: "GPU"
            value: ResourceUsage.gpuUsage
        }
        LoadRow {
            Layout.fillWidth: true
            visible: !ResourceUsage.gpuAvailable && ResourceUsage.swapTotal > 0
            icon: "swap_horiz"
            label: "Swap"
            value: ResourceUsage.swapUsedPercentage
        }
        Item { Layout.fillHeight: true }
    }
}
