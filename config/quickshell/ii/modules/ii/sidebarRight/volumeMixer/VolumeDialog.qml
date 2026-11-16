pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.sidebarRight.controls
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire

// Audio page of the right rail: output / input switch, master volume, device
// list (one click to change) and per-application volumes.
RailPage {
    id: root
    property bool isSink: true
    title: root.isSink ? Translation.tr("Audio output") : Translation.tr("Audio input")

    readonly property PwNode master: isSink ? Audio.sink : Audio.source
    readonly property bool muted: master?.audio?.muted ?? false
    readonly property bool auto: isSink ? Audio.outputAuto : Audio.inputAuto
    readonly property list<var> devices: isSink ? Audio.outputDevices : Audio.inputDevices
    readonly property list<var> apps: isSink ? Audio.outputAppNodes : Audio.inputAppNodes
    readonly property int defaultId: (isSink ? Pipewire.defaultAudioSink?.id : Pipewire.defaultAudioSource?.id) ?? -1

    actions: [
        HeaderButton {
            anchors.verticalCenter: parent.verticalCenter
            buttonIcon: root.isSink ? "volume_off" : "mic_off"
            tooltip: root.muted ? Translation.tr("Click to unmute") : Translation.tr("Click to mute")
            toggled: root.muted
            enabled: root.master !== null
            onClicked: root.master.audio.muted = !root.muted
        }
    ]

    footer: [
        RailButton {
            symbol: "open_in_new"
            label: Translation.tr("Volume mixer")
            onClicked: {
                Quickshell.execDetached(["bash", "-c", `${Config.options.apps.volumeMixer}`]);
                GlobalStates.sidebarRightOpen = false;
            }
        }
    ]

    Row { // Output / input
        id: directionSwitch
        Layout.fillWidth: true
        spacing: 8
        Repeater {
            model: [
                { sink: true, label: Translation.tr("Output"), symbol: "volume_up" },
                { sink: false, label: Translation.tr("Input"), symbol: "mic" }
            ]
            RailButton {
                required property var modelData
                width: (directionSwitch.width - directionSwitch.spacing) / 2
                implicitHeight: 38
                primary: root.isSink === modelData.sink
                symbol: modelData.symbol
                label: modelData.label
                onClicked: root.isSink = modelData.sink
            }
        }
    }

    ControlSlider {
        Layout.fillWidth: true
        icon: root.isSink ? (root.muted ? "volume_off" : "volume_up") : (root.muted ? "mic_off" : "mic")
        value: root.master?.audio?.volume ?? 0
        onMoved: newValue => {
            if (root.master?.audio)
                root.master.audio.volume = newValue;
        }
    }

    StyledFlickable {
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        contentHeight: list.implicitHeight

        Column {
            id: list
            width: parent.width
            spacing: 6

            RailSection {
                text: Translation.tr("Device")
            }
            RailRow {
                width: parent.width
                interactive: true
                highlighted: root.auto
                icon: "auto_awesome"
                title: Translation.tr("Automatic")
                subtitle: root.auto && root.master ? Audio.friendlyDeviceName(root.master) : ""
                onClicked: {
                    if (root.isSink)
                        Audio.setAutoSink();
                    else
                        Audio.setAutoSource();
                }
                MaterialSymbol {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.auto
                    text: "check"
                    iconSize: 20
                    color: Appearance.colors.colPrimary
                }
            }
            Repeater {
                model: ScriptModel {
                    values: root.devices
                }
                delegate: RailRow {
                    id: deviceRow
                    required property var modelData
                    readonly property bool current: !root.auto && modelData.id === root.defaultId
                    width: list.width
                    interactive: true
                    highlighted: current
                    icon: root.isSink ? "speaker" : "mic_external_on"
                    title: Audio.friendlyDeviceName(modelData)
                    onClicked: {
                        if (root.isSink)
                            Audio.setDefaultSink(modelData);
                        else
                            Audio.setDefaultSource(modelData);
                    }
                    MaterialSymbol {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: deviceRow.current
                        text: "check"
                        iconSize: 20
                        color: Appearance.colors.colPrimary
                    }
                }
            }

            RailSection {
                text: root.apps.length > 0 ? Translation.tr("Applications") : Translation.tr("No applications")
            }
            Repeater {
                model: ScriptModel {
                    values: root.apps
                }
                delegate: AudioAppRow {
                    required property var modelData
                    node: modelData
                    width: list.width
                }
            }
        }
    }
}
