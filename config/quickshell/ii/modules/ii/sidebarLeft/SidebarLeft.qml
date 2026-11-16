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

    PanelWindow {
        id: panelWindow
        visible: rail.mapped

        function hide() {
            GlobalStates.sidebarLeftOpen = false;
        }
        function syncFocusGrab() {
            if (GlobalStates.sidebarLeftOpen && visible)
                GlobalFocusGrab.addDismissable(panelWindow);
            else if (!GlobalStates.sidebarLeftOpen)
                GlobalFocusGrab.removeDismissable(panelWindow);
        }

        exclusiveZone: 0
        implicitWidth: rail.windowWidth
        WlrLayershell.namespace: "quickshell:sidebarLeft"
        WlrLayershell.keyboardFocus: GlobalStates.sidebarLeftOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        color: "transparent"

        anchors {
            top: true
            left: true
            bottom: true
        }

        mask: Region {
            item: GlobalStates.sidebarLeftOpen ? rail.hitbox : null
        }

        onVisibleChanged: syncFocusGrab()
        Connections {
            target: GlobalStates
            function onSidebarLeftOpenChanged() {
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
            open: GlobalStates.sidebarLeftOpen
            surfaceReady: panelWindow.backingWindowVisible

            SidebarLeftContent {
                rail: rail
                focus: GlobalStates.sidebarLeftOpen
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Escape) {
                        panelWindow.hide();
                    }
                }
            }
        }
    }

    IpcHandler {
        target: "sidebarLeft"

        function toggle(): void {
            GlobalStates.sidebarLeftOpen = !GlobalStates.sidebarLeftOpen
        }

        function close(): void {
            GlobalStates.sidebarLeftOpen = false
        }

        function open(): void {
            GlobalStates.sidebarLeftOpen = true
        }
    }

    GlobalShortcut {
        name: "sidebarLeftToggle"
        description: "Toggles left sidebar on press"

        onPressed: {
            GlobalStates.sidebarLeftOpen = !GlobalStates.sidebarLeftOpen;
        }
    }

    GlobalShortcut {
        name: "sidebarLeftOpen"
        description: "Opens left sidebar on press"

        onPressed: {
            GlobalStates.sidebarLeftOpen = true;
        }
    }

    GlobalShortcut {
        name: "sidebarLeftClose"
        description: "Closes left sidebar on press"

        onPressed: {
            GlobalStates.sidebarLeftOpen = false;
        }
    }
}
