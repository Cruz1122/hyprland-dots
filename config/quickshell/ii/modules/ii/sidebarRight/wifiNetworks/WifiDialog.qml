pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.services.network
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.sidebarRight.controls
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

// Wi-Fi page of the right rail: rescan and connection details in the header, the
// current network on top, then the networks in range.
RailPage {
    id: root
    title: Translation.tr("Wi-Fi")
    busy: Network.wifiEnabled && (Network.wifiScanning || Network.wifiConnecting)

    readonly property WifiAccessPoint current: Network.active
    readonly property list<var> others: Network.friendlyWifiNetworks.filter(network => !network.active)

    function strengthIcon(strength) {
        return strength > 80 ? "signal_wifi_4_bar" : strength > 60 ? "network_wifi_3_bar"
            : strength > 40 ? "network_wifi_2_bar" : strength > 20 ? "network_wifi_1_bar" : "signal_wifi_0_bar";
    }
    function band(frequency) {
        return frequency >= 5925 ? "6 GHz" : frequency >= 4900 ? "5 GHz" : frequency > 0 ? "2.4 GHz" : "";
    }
    function describe(network) {
        if (!network)
            return "";
        const parts = [network.isSecure ? Translation.tr("Secured") : Translation.tr("Open network"), root.band(network.frequency), `${network.strength}%`];
        return parts.filter(part => part.length > 0).join("  ·  ");
    }

    // Connection details, read on demand from NetworkManager.
    property bool infoOpen: false
    property var info: []
    onInfoOpenChanged: if (infoOpen) infoProc.running = true
    function parseInfo(text) {
        const fields = {};
        for (const line of text.split("\n")) {
            const separator = line.indexOf(":");
            if (separator < 0)
                continue;
            const key = line.slice(0, separator).replace(/\[\d+\]$/, "");
            // nmcli -t escapes the colons inside values.
            const value = line.slice(separator + 1).replace(/\\:/g, ":").trim();
            if (value.length === 0)
                continue;
            fields[key] = fields[key] ? `${fields[key]}, ${value}` : value;
        }
        const wifi = (fields["WIFI"] ?? "").split("|");
        const entries = [
            [Translation.tr("Network"), fields["GENERAL.CONNECTION"]],
            [Translation.tr("Interface"), fields["GENERAL.DEVICE"]],
            ["IPv4", fields["IP4.ADDRESS"]],
            [Translation.tr("Gateway"), fields["IP4.GATEWAY"]],
            ["DNS", fields["IP4.DNS"]],
            ["IPv6", fields["IP6.ADDRESS"]],
            ["MAC", fields["GENERAL.HWADDR"]],
            [Translation.tr("Channel"), wifi[0]],
            [Translation.tr("Link speed"), wifi[1]],
            [Translation.tr("Security"), wifi[2]]
        ];
        return entries.filter(entry => entry[1] && entry[1] !== "--").map(entry => ({ label: entry[0], value: entry[1] }));
    }
    Process { // `--rescan no`: otherwise it waits for the scan the page starts on open
        id: infoProc
        environment: ({
            LANG: "C",
            LC_ALL: "C"
        })
        command: ["bash", "-c", `dev=$(nmcli -t -f DEVICE,TYPE,STATE device | awk -F: '$3=="connected" && ($2=="wifi"||$2=="ethernet"){print $1; exit}')
[ -n "$dev" ] || exit 0
nmcli -t -f GENERAL.DEVICE,GENERAL.CONNECTION,GENERAL.HWADDR,IP4.ADDRESS,IP4.GATEWAY,IP4.DNS,IP6.ADDRESS device show "$dev"
nmcli -t -f ACTIVE,CHAN,RATE,SECURITY dev wifi list --rescan no | awk -F: '$1=="yes"{print "WIFI:" $2 "|" $3 "|" $4; exit}'`]
        stdout: StdioCollector {
            onStreamFinished: root.info = root.parseInfo(text)
        }
    }

    Connections {
        target: Network
        // Keep the open sheet in step with the connection.
        function onActiveChanged() {
            if (root.infoOpen)
                infoProc.running = true;
        }
        // Turning the radio on from here should fill the list right away.
        function onWifiEnabledChanged() {
            if (Network.wifiEnabled && root.show)
                Network.rescanWifi();
        }
    }

    actions: [
        HeaderButton {
            anchors.verticalCenter: parent.verticalCenter
            buttonIcon: "refresh"
            tooltip: Translation.tr("Scan again")
            enabled: Network.wifiEnabled && !Network.wifiScanning
            opacity: enabled ? 1 : 0.4
            onClicked: Network.rescanWifi()
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
            label: Translation.tr("Network settings")
            onClicked: {
                Quickshell.execDetached(["bash", "-c", `${Network.ethernet ? Config.options.apps.networkEthernet : Config.options.apps.network}`]);
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
                emptyText: infoProc.running ? "…" : Translation.tr("Not connected")
            }

            Column { // Radio off
                width: parent.width
                visible: !Network.wifiEnabled
                topPadding: 60
                spacing: 10
                MaterialSymbol {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "signal_wifi_off"
                    iconSize: 44
                    color: Appearance.colors.colSubtext
                }
                StyledText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Translation.tr("Wi-Fi is off")
                    color: Appearance.colors.colSubtext
                }
                RailButton {
                    anchors.horizontalCenter: parent.horizontalCenter
                    primary: true
                    label: Translation.tr("Turn on")
                    onClicked: Network.enableWifi(true)
                }
            }

            RailSection {
                visible: Network.wifiEnabled && root.current !== null
                text: Translation.tr("Current network")
            }
            RailRow {
                width: parent.width
                visible: Network.wifiEnabled && root.current !== null
                highlighted: true
                icon: root.strengthIcon(root.current?.strength ?? 0)
                title: root.current?.ssid ?? ""
                subtitle: root.describe(root.current)

                RailButton {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !(root.current?.isSecure ?? true)
                    symbol: "captive_portal"
                    onClicked: {
                        Network.openPublicWifiPortal();
                        GlobalStates.sidebarRightOpen = false;
                    }
                    StyledToolTip {
                        text: Translation.tr("Open network portal")
                    }
                }
                RailButton {
                    anchors.verticalCenter: parent.verticalCenter
                    symbol: "delete"
                    onClicked: Network.forgetWifiNetwork(root.current.ssid)
                    StyledToolTip {
                        text: Translation.tr("Forget")
                    }
                }
                RailButton {
                    anchors.verticalCenter: parent.verticalCenter
                    label: Translation.tr("Disconnect")
                    onClicked: Network.disconnectWifiNetwork()
                }
            }

            RailSection {
                visible: Network.wifiEnabled
                text: root.others.length > 0 ? Translation.tr("Available networks") + `  ·  ${root.others.length}`
                    : Network.wifiScanning ? Translation.tr("Looking for networks…") : Translation.tr("No networks found")
            }
            Repeater {
                model: ScriptModel {
                    values: Network.wifiEnabled ? root.others : []
                }
                delegate: WifiNetworkItem {
                    required property WifiAccessPoint modelData
                    wifiNetwork: modelData
                    width: list.width
                    summary: root.describe(modelData)
                    signalIcon: root.strengthIcon(modelData.strength)
                }
            }
        }
    }
}
