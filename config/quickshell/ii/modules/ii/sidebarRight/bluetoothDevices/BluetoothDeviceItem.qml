import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.sidebarRight.controls
import qs.services
import QtQuick
import Quickshell.Bluetooth

// A Bluetooth device with its actions in the row: connect / disconnect, and
// forget for paired ones.
RailRow {
    id: root
    required property var device
    readonly property bool connected: device?.connected ?? false
    readonly property bool paired: device?.paired ?? false
    readonly property bool pairing: device?.pairing ?? false
    readonly property bool connecting: device?.state === BluetoothDeviceState.Connecting
    readonly property bool working: pairing || connecting

    highlighted: connected
    icon: Icons.getBluetoothDeviceMaterialSymbol(device?.icon || "")
    title: device?.name || Translation.tr("Unknown device")
    subtitle: {
        if (root.pairing)
            return Translation.tr("Pairing…");
        if (root.connecting)
            return Translation.tr("Connecting…");
        if (!root.paired && !root.connected)
            return "";
        let status = root.connected ? Translation.tr("Connected") : Translation.tr("Paired");
        if (root.device?.batteryAvailable)
            status += `  ·  ${Math.round(root.device.battery * 100)}%`;
        return status;
    }

    RailButton {
        anchors.verticalCenter: parent.verticalCenter
        visible: root.paired && root.hovered
        symbol: "delete"
        onClicked: root.device.forget()
        StyledToolTip {
            text: Translation.tr("Forget")
        }
    }
    RailButton {
        anchors.verticalCenter: parent.verticalCenter
        // Filled only under the pointer: a column of filled buttons would
        // outweigh the device names.
        primary: !root.connected && root.hovered
        enabled: !root.working
        label: root.connected ? Translation.tr("Disconnect") : Translation.tr("Connect")
        onClicked: {
            if (root.connected)
                root.device.disconnect();
            else
                root.device.connect();
        }
    }
}
