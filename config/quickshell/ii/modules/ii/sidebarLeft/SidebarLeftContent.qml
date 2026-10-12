import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.mediaControls
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.UPower

Item {
    id: root
    required property var scopeRoot
    property int sidebarPadding: 10
    anchors.fill: parent

    Timer {
        id: actionTimer
        property var triggerAction: null
        interval: 300
        repeat: false
        onTriggered: if (triggerAction) triggerAction()
    }

    function delayedAction(action) {
        GlobalStates.sidebarLeftOpen = false;
        actionTimer.triggerAction = action;
        actionTimer.restart();
    }

    component ActionButton: GroupButton {
        id: actionButton
        required property string iconName
        required property string title
        property string status: ""
        property var triggerAction: null
        baseWidth: 40
        baseHeight: 40
        clickedWidth: 60
        buttonRadius: Math.min(baseWidth, baseHeight) / 2
        buttonRadiusPressed: Appearance.rounding.small

        onClicked: {
            if (actionButton.triggerAction)
                actionButton.triggerAction();
        }

        contentItem: MaterialSymbol {
            anchors.centerIn: parent
            text: actionButton.iconName
            iconSize: 22
            fill: actionButton.down ? 1 : 0
            color: Appearance.colors.colOnLayer1
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }

        StyledToolTip {
            text: actionButton.status.length > 0
                ? `${actionButton.title}\n${actionButton.status}`
                : actionButton.title
        }
    }

    function screenshot() {
        root.delayedAction(() => Quickshell.execDetached([
            "qs", "-p", Quickshell.shellPath(""), "ipc", "call", "region", "screenshot"
        ]));
    }

    function startRecording() {
        const action = Config.options.screenRecord.barButtonAction ?? "fullscreen";
        if (action === "region") {
            const regionAction = Config.options.screenRecord.recordAudioByDefault ? "recordWithSound" : "record";
            Quickshell.execDetached(["qs", "-p", Quickshell.shellPath(""), "ipc", "call", "region", regionAction]);
        } else if (action === "pause") {
            Quickshell.execDetached([Directories.recordScriptPath, "--pause"]);
        } else if (action === "stop") {
            Quickshell.execDetached([Directories.recordScriptPath, "--stop"]);
        } else {
            const command = [Directories.recordScriptPath, "--fullscreen"];
            if (Config.options.screenRecord.recordAudioByDefault) {
                const source = Config.options.screenRecord.audioSource ?? "system";
                if (source === "system") command.push("--sound");
                else if (source === "mic") command.push("--mic");
                else if (source === "both") {
                    command.push("--sound");
                    command.push("--mic");
                }
            }
            Quickshell.execDetached(command);
        }
    }

    function cyclePowerProfile() {
        if (PowerProfiles.hasPerformanceProfile) {
            switch (PowerProfiles.profile) {
            case PowerProfile.PowerSaver: PowerProfiles.profile = PowerProfile.Balanced; break;
            case PowerProfile.Balanced: PowerProfiles.profile = PowerProfile.Performance; break;
            case PowerProfile.Performance: PowerProfiles.profile = PowerProfile.PowerSaver; break;
            }
        } else {
            PowerProfiles.profile = PowerProfiles.profile === PowerProfile.Balanced
                ? PowerProfile.PowerSaver : PowerProfile.Balanced;
        }
    }

    function powerProfileName() {
        switch (PowerProfiles.profile) {
        case PowerProfile.PowerSaver: return Translation.tr("Power Saver");
        case PowerProfile.Performance: return Translation.tr("Performance");
        default: return Translation.tr("Balanced");
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: root.sidebarPadding
        spacing: root.sidebarPadding

        RowLayout {
            Layout.fillWidth: true
            spacing: root.sidebarPadding

            Item { Layout.fillWidth: true }

            ActionButton {
                iconName: "delete_forever"
                title: Translation.tr("Task killer")
                triggerAction: () => root.delayedAction(() => Quickshell.execDetached(["qs", "-p", Quickshell.shellPath("taskKiller.qml")]))
            }
            ActionButton {
                iconName: "screenshot_region"
                title: Translation.tr("Screenshot")
                triggerAction: root.screenshot
            }
            ActionButton {
                iconName: "videocam"
                title: Translation.tr("Screen record")
                triggerAction: () => root.delayedAction(root.startRecording)
            }
            ActionButton {
                iconName: "colorize"
                title: Translation.tr("Color picker")
                triggerAction: () => root.delayedAction(() => Quickshell.execDetached(["hyprpicker", "-a"]))
            }
            ActionButton {
                iconName: PowerProfiles.profile === PowerProfile.PowerSaver ? "energy_savings_leaf"
                    : PowerProfiles.profile === PowerProfile.Performance ? "local_fire_department" : "airwave"
                title: Translation.tr("Power mode")
                status: root.powerProfileName()
                triggerAction: root.cyclePowerProfile
            }

            Item { Layout.fillWidth: true }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 240
            color: Appearance.colors.colLayer1
            radius: Appearance.rounding.normal
            clip: true

            NotesPage {
                anchors.fill: parent
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 240
            Layout.maximumHeight: 240
            color: Appearance.colors.colLayer1
            radius: Appearance.rounding.normal
            clip: true

            Loader {
                anchors.fill: parent
                anchors.margins: 4
                active: !!MprisController.activePlayer
                sourceComponent: PlayerControl {
                    player: MprisController.activePlayer
                    visualizerPoints: []
                    radius: Appearance.rounding.normal
                    width: parent.width
                    height: parent.height
                }
            }

            ColumnLayout {
                anchors.centerIn: parent
                visible: !MprisController.activePlayer
                spacing: 4
                MaterialSymbol {
                    Layout.alignment: Qt.AlignHCenter
                    text: "music_off"
                    iconSize: Appearance.font.pixelSize.huge
                    color: Appearance.colors.colSubtext
                }
                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: Translation.tr("No active player")
                    color: Appearance.colors.colSubtext
                }
            }
        }
    }
}
