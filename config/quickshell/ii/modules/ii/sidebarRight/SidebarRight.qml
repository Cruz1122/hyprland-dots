import qs
import qs.services
import qs.modules.common
import qs.modules.ii.sideRail
import QtQuick
import Quickshell.Io
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: root
    property int sidebarWidth: 440

    PanelWindow {
        id: panelWindow
        visible: rail.mapped

        function hide() {
            GlobalStates.sidebarRightOpen = false;
        }
        function syncFocusGrab() {
            if (GlobalStates.sidebarRightOpen && visible)
                GlobalFocusGrab.addDismissable(panelWindow);
            else if (!GlobalStates.sidebarRightOpen)
                GlobalFocusGrab.removeDismissable(panelWindow);
        }

        exclusiveZone: 0
        implicitWidth: rail.windowWidth
        WlrLayershell.namespace: "quickshell:sidebarRight"
        WlrLayershell.keyboardFocus: GlobalStates.sidebarRightOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        color: "transparent"

        anchors {
            top: true
            right: true
            bottom: true
        }

        mask: Region {
            item: GlobalStates.sidebarRightOpen ? rail.hitbox : null
        }

        onVisibleChanged: syncFocusGrab()
        Connections {
            target: GlobalStates
            function onSidebarRightOpenChanged() {
                panelWindow.syncFocusGrab();
            }
        }
        Connections {
            target: GlobalFocusGrab
            function onDismissed() {
                panelWindow.hide();
            }
        }

        SideRail {
            id: rail
            anchors.fill: parent
            rightSide: true
            railWidth: root.sidebarWidth
            open: GlobalStates.sidebarRightOpen
            surfaceReady: panelWindow.backingWindowVisible

            Loader {
                id: sidebarContentLoader
                active: GlobalStates.sidebarRightOpen || rail.mapped || Config?.options.sidebar.keepRightSidebarLoaded
                anchors.fill: parent

                focus: GlobalStates.sidebarRightOpen
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Escape) {
                        panelWindow.hide();
                    }
                }

                sourceComponent: SidebarRightContent {
                    rail: rail
                }
            }
        }
    }

    IpcHandler {
        target: "sidebarRight"

        function toggle(): void {
            GlobalStates.sidebarRightOpen = !GlobalStates.sidebarRightOpen;
        }

        function close(): void {
            GlobalStates.sidebarRightOpen = false;
        }

        function open(): void {
            GlobalStates.sidebarRightOpen = true;
        }
    }

    GlobalShortcut {
        name: "sidebarRightToggle"
        description: "Toggles right sidebar on press"

        onPressed: {
            GlobalStates.sidebarRightOpen = !GlobalStates.sidebarRightOpen;
        }
    }
    GlobalShortcut {
        name: "sidebarRightOpen"
        description: "Opens right sidebar on press"

        onPressed: {
            GlobalStates.sidebarRightOpen = true;
        }
    }
    GlobalShortcut {
        name: "sidebarRightClose"
        description: "Closes right sidebar on press"

        onPressed: {
            GlobalStates.sidebarRightOpen = false;
        }
    }
}
