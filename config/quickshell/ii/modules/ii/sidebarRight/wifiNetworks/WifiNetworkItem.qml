import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.sidebarRight.controls
import qs.services
import qs.services.network
import QtQuick

// A network in range: click (or the button) connects; a missing or wrong
// password unfolds the prompt under the row.
Column {
    id: root
    required property WifiAccessPoint wifiNetwork
    property string summary: ""
    property string signalIcon: "signal_wifi_0_bar"
    readonly property bool connecting: Network.wifiConnectTarget === root.wifiNetwork
    readonly property bool askingPassword: root.wifiNetwork?.askingPassword ?? false

    spacing: 4

    function submitPassword() {
        if (passwordField.text.length === 0)
            return;
        Network.changePassword(root.wifiNetwork, passwordField.text);
        passwordField.text = "";
    }

    RailRow {
        id: row
        width: parent.width
        icon: root.signalIcon
        title: root.wifiNetwork?.ssid ?? Translation.tr("Unknown")
        subtitle: root.connecting ? Translation.tr("Connecting…") : root.summary
        interactive: !root.connecting && !root.askingPassword && !Network.wifiConnecting
        onClicked: Network.connectToWifiNetwork(root.wifiNetwork)

        MaterialSymbol {
            anchors.verticalCenter: parent.verticalCenter
            visible: (root.wifiNetwork?.isSecure ?? false) && !connectButton.visible
            text: "lock"
            iconSize: 18
            color: Appearance.colors.colSubtext
        }
        RailButton {
            id: connectButton
            anchors.verticalCenter: parent.verticalCenter
            visible: row.hovered && row.interactive
            primary: true
            label: Translation.tr("Connect")
            onClicked: Network.connectToWifiNetwork(root.wifiNetwork)
        }
    }

    Rectangle { // Password prompt
        width: parent.width
        visible: root.askingPassword
        implicitHeight: prompt.implicitHeight + 20
        radius: Appearance.rounding.normal
        color: Appearance.colors.colLayer1
        onVisibleChanged: if (visible) passwordField.forceActiveFocus()

        Column {
            id: prompt
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: 10
            }
            spacing: 8

            Row {
                width: parent.width
                spacing: 6
                MaterialTextField {
                    id: passwordField
                    width: parent.width - revealButton.width - parent.spacing
                    placeholderText: Translation.tr("Password")
                    echoMode: revealButton.revealed ? TextInput.Normal : TextInput.Password
                    inputMethodHints: Qt.ImhSensitiveData
                    onAccepted: root.submitPassword()
                }
                RailButton {
                    id: revealButton
                    property bool revealed: false
                    anchors.verticalCenter: parent.verticalCenter
                    symbol: revealed ? "visibility_off" : "visibility"
                    onClicked: revealed = !revealed
                }
            }
            Row {
                anchors.right: parent.right
                spacing: 6
                RailButton {
                    label: Translation.tr("Cancel")
                    onClicked: {
                        passwordField.text = "";
                        root.wifiNetwork.askingPassword = false;
                    }
                }
                RailButton {
                    primary: true
                    enabled: passwordField.text.length > 0
                    label: Translation.tr("Connect")
                    onClicked: root.submitPassword()
                }
            }
        }
    }
}
