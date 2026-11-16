import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Hyprland

import qs.modules.ii.sidebarRight.controls
import qs.modules.ii.sidebarRight.quickToggles

import qs.modules.ii.sidebarRight.bluetoothDevices
import qs.modules.ii.sidebarRight.nightLight
import qs.modules.ii.sidebarRight.volumeMixer
import qs.modules.ii.sidebarRight.wifiNetworks

Item {
    id: root
    // SideRail hosting this content; drives the staggered entrance.
    property var rail: null
    property int sidebarPadding: 16
    property string settingsQmlPath: Quickshell.shellPath("settings.qml")
    property bool showAudioOutputDialog: false
    property bool showAudioInputDialog: false
    property bool showBluetoothDialog: false
    property bool showNightLightDialog: false
    property bool showWifiDialog: false
    property bool editMode: false

    Connections {
        target: GlobalStates
        function onSidebarRightOpenChanged() {
            if (!GlobalStates.sidebarRightOpen) {
                root.showWifiDialog = false;
                root.showBluetoothDialog = false;
                root.showAudioOutputDialog = false;
                root.showAudioInputDialog = false;
            }
        }
    }

    function stage(index) {
        return root.rail ? root.rail.stage(index) : 1;
    }
    function stageOffset(index) {
        return root.rail ? root.rail.stageOffset(index) : 0;
    }

    // Top to bottom: system actions, control (tiles, bars), tools (accordion) and
    // inbox (notifications). Everything stacks from the top, so spare height
    // ends up below the notifications instead of between blocks.
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: root.sidebarPadding
        spacing: 8

        SystemButtonRow {
            Layout.fillWidth: true
            opacity: root.stage(0)
            transform: Translate { x: root.stageOffset(0) }
        }

        ControlGrid {
            id: controlGrid
            Layout.fillWidth: true
            visible: !root.editMode
            opacity: root.stage(1)
            transform: Translate { x: root.stageOffset(1) }
            onOpenAudioOutputDialog: root.showAudioOutputDialog = true
            onOpenAudioInputDialog: root.showAudioInputDialog = true
            onOpenBluetoothDialog: root.showBluetoothDialog = true
            onOpenNightLightDialog: root.showNightLightDialog = true
            onOpenWifiDialog: root.showWifiDialog = true
        }

        Loader { // The stock panel, only as the editor for the toggle list
            Layout.fillWidth: true
            visible: active
            active: root.editMode
            sourceComponent: AndroidQuickPanel {
                editMode: true
            }
        }

        ControlSliders {
            Layout.fillWidth: true
            opacity: root.stage(2)
            transform: Translate { x: root.stageOffset(2) }
        }

        BottomWidgetGroup {
            Layout.fillWidth: true
            Layout.topMargin: 8
            Layout.preferredHeight: implicitHeight
            opacity: root.stage(3)
            transform: Translate { x: root.stageOffset(3) }
        }

        CenterWidgetGroup {
            Layout.fillHeight: true
            Layout.fillWidth: true
            Layout.topMargin: 10
            color: "transparent"
            opacity: root.stage(4)
            transform: Translate { x: root.stageOffset(4) }
        }
    }

    ToggleDialog {
        shownPropertyString: "showAudioOutputDialog"
        dialog: VolumeDialog {
            isSink: true
        }
    }

    ToggleDialog {
        shownPropertyString: "showAudioInputDialog"
        dialog: VolumeDialog {
            isSink: false
        }
    }

    ToggleDialog {
        shownPropertyString: "showBluetoothDialog"
        dialog: BluetoothDialog {}
        onShownChanged: {
            const adapter = Bluetooth.defaultAdapter;
            if (!adapter)
                return;
            // Opening the page looks for devices but never turns the radio on.
            adapter.discovering = shown && adapter.enabled;
        }
    }

    ToggleDialog {
        shownPropertyString: "showNightLightDialog"
        dialog: NightLightDialog {}
    }

    ToggleDialog {
        shownPropertyString: "showWifiDialog"
        dialog: WifiDialog {}
        onShownChanged: {
            // Opening the page rescans but never turns the radio on.
            if (shown && Network.wifiEnabled)
                Network.rescanWifi();
        }
    }

    component ToggleDialog: Loader {
        id: toggleDialogLoader
        required property string shownPropertyString
        property alias dialog: toggleDialogLoader.sourceComponent
        readonly property bool shown: root[shownPropertyString]
        anchors.fill: parent

        onShownChanged: if (shown) toggleDialogLoader.active = true;
        active: shown
        onActiveChanged: {
            if (active) {
                item.show = true;
                item.forceActiveFocus();
            }
        }
        Connections {
            target: toggleDialogLoader.item
            function onDismiss() {
                toggleDialogLoader.item.show = false
                root[toggleDialogLoader.shownPropertyString] = false;
            }
            function onVisibleChanged() {
                if (!toggleDialogLoader.item.visible && !root[toggleDialogLoader.shownPropertyString]) toggleDialogLoader.active = false;
            }
        }
    }

    component SystemButtonRow: Item {
        implicitHeight: systemButtonsRow.implicitHeight

        Row {
            id: systemButtonsRow
            anchors {
                verticalCenter: parent.verticalCenter
                right: parent.right
            }
            spacing: 2

            HeaderButton {
                toggled: root.editMode
                buttonIcon: "edit"
                tooltip: Translation.tr("Edit quick toggles") + (root.editMode ? Translation.tr("\nLMB to enable/disable\nRMB to toggle size\nScroll to swap position") : "")
                onClicked: root.editMode = !root.editMode
            }
            HeaderButton {
                buttonIcon: "restart_alt"
                tooltip: Translation.tr("Reload Hyprland & Quickshell")
                onClicked: {
                    Quickshell.execDetached(["hyprctl", "reload"])
                    Quickshell.reload(true);
                }
            }
            HeaderButton {
                buttonIcon: "settings"
                tooltip: Translation.tr("Settings")
                onClicked: {
                    GlobalStates.sidebarRightOpen = false;
                    // The launcher focuses an open settings window instead of starting a second one.
                    Quickshell.execDetached(["env", `II_SETTINGS_QML=${root.settingsQmlPath}`, Quickshell.shellPath("scripts/settings/open-settings.sh")]);
                }
            }
            HeaderButton {
                buttonIcon: "power_settings_new"
                tooltip: Translation.tr("Session")
                onClicked: GlobalStates.sessionOpen = true
            }
        }
    }
}
