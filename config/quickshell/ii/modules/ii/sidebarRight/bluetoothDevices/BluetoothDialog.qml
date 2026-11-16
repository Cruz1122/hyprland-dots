pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.sidebarRight.controls
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth

// Bluetooth page of the right rail: scan and adapter details in the header,
// devices grouped by state, every action one click away.
RailPage {
    id: root
    title: Translation.tr("Bluetooth")

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool radioOn: adapter?.enabled ?? false
    readonly property bool discovering: adapter?.discovering ?? false
    // Nameless devices show up as bare addresses: noise in a "nearby" list.
    readonly property list<var> nearby: BluetoothStatus.unpairedDevices.filter(device => {
        const name = device.name ?? "";
        return name.length > 0 && !/^([0-9A-F]{2}[-:]){5}[0-9A-F]{2}$/i.test(name);
    })
    busy: radioOn && discovering

    // Adapter details (read on demand) plus the address of each connected device.
    property bool infoOpen: false
    property var adapterInfo: []
    readonly property var info: adapterInfo.concat(BluetoothStatus.connectedDevices.map(device => ({
        label: device.name || Translation.tr("Unknown device"),
        value: device.address ?? ""
    })).filter(entry => entry.value.length > 0))
    onInfoOpenChanged: if (infoOpen) infoProc.running = true
    function parseInfo(text) {
        const field = name => (text.match(new RegExp(`^\\s*${name}: (.*)$`, "m")) ?? [])[1] ?? "";
        const yesNo = value => value === "yes" ? Translation.tr("Yes") : Translation.tr("No");
        const entries = [
            [Translation.tr("Adapter"), field("Alias") || field("Name")],
            [Translation.tr("Address"), (text.match(/^Controller (\S+)/m) ?? [])[1] ?? ""],
            [Translation.tr("Visible to others"), field("Discoverable") ? yesNo(field("Discoverable")) : ""],
            [Translation.tr("Accepts pairing"), field("Pairable") ? yesNo(field("Pairable")) : ""]
        ];
        return entries.filter(entry => entry[1].length > 0).map(entry => ({ label: entry[0], value: entry[1] }));
    }
    Process {
        id: infoProc
        environment: ({
            LANG: "C",
            LC_ALL: "C"
        })
        command: ["bluetoothctl", "show"]
        stdout: StdioCollector {
            onStreamFinished: root.adapterInfo = root.parseInfo(text)
        }
    }

    function scan() {
        if (!root.adapter || !root.radioOn)
            return;
        root.adapter.discovering = false;
        restartScan.restart();
    }
    Timer {
        id: restartScan
        interval: 300
        onTriggered: if (root.adapter && root.radioOn && root.show) root.adapter.discovering = true
    }
    onRadioOnChanged: {
        if (radioOn && show)
            restartScan.restart();
        if (infoOpen)
            infoProc.running = true;
    }

    actions: [
        HeaderButton {
            anchors.verticalCenter: parent.verticalCenter
            buttonIcon: root.discovering ? "close" : "refresh"
            tooltip: root.discovering ? Translation.tr("Stop scanning") : Translation.tr("Scan again")
            enabled: root.radioOn
            opacity: enabled ? 1 : 0.4
            onClicked: {
                if (root.discovering)
                    root.adapter.discovering = false;
                else
                    root.scan();
            }
        },
        HeaderButton {
            anchors.verticalCenter: parent.verticalCenter
            buttonIcon: "info"
            tooltip: Translation.tr("Connection details")
            toggled: root.infoOpen
            onClicked: root.infoOpen = !root.infoOpen
        }
    ]

    footer: [
        RailButton {
            symbol: "open_in_new"
            label: Translation.tr("Bluetooth settings")
            onClicked: {
                Quickshell.execDetached(["bash", "-c", `${Config.options.apps.bluetooth}`]);
                GlobalStates.sidebarRightOpen = false;
            }
        }
    ]

    StyledFlickable {
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        contentHeight: list.implicitHeight

        Column {
            id: list
            width: parent.width
            spacing: 6

            RailInfoCard {
                width: parent.width
                visible: root.infoOpen
                entries: root.info
                emptyText: infoProc.running ? "…" : Translation.tr("No Bluetooth adapter")
            }

            Column { // Radio off or missing
                width: parent.width
                visible: !root.radioOn
                topPadding: 60
                spacing: 10
                MaterialSymbol {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "bluetooth_disabled"
                    iconSize: 44
                    color: Appearance.colors.colSubtext
                }
                StyledText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.adapter ? Translation.tr("Bluetooth is off") : Translation.tr("No Bluetooth adapter")
                    color: Appearance.colors.colSubtext
                }
                RailButton {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: root.adapter !== null
                    primary: true
                    label: Translation.tr("Turn on")
                    onClicked: root.adapter.enabled = true
                }
            }

            RailSection {
                visible: root.radioOn && BluetoothStatus.connectedDevices.length > 0
                text: Translation.tr("Connected devices")
            }
            Repeater {
                model: ScriptModel {
                    values: root.radioOn ? BluetoothStatus.connectedDevices : []
                }
                delegate: BluetoothDeviceItem {
                    required property BluetoothDevice modelData
                    device: modelData
                    width: list.width
                }
            }

            RailSection {
                visible: root.radioOn && BluetoothStatus.pairedButNotConnectedDevices.length > 0
                text: Translation.tr("Paired devices")
            }
            Repeater {
                model: ScriptModel {
                    values: root.radioOn ? BluetoothStatus.pairedButNotConnectedDevices : []
                }
                delegate: BluetoothDeviceItem {
                    required property BluetoothDevice modelData
                    device: modelData
                    width: list.width
                }
            }

            RailSection {
                visible: root.radioOn
                text: root.nearby.length > 0 ? Translation.tr("Nearby devices") + `  ·  ${root.nearby.length}`
                    : root.discovering ? Translation.tr("Looking for devices…") : Translation.tr("No devices found")
            }
            Repeater {
                model: ScriptModel {
                    values: root.radioOn ? root.nearby : []
                }
                delegate: BluetoothDeviceItem {
                    required property BluetoothDevice modelData
                    device: modelData
                    width: list.width
                }
            }
        }
    }
}
