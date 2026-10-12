pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: root

    readonly property var monitors: HyprlandData.allMonitors ?? []
    readonly property bool hasLaptop: monitors.some(monitor => monitor.name.startsWith("eDP-") || monitor.name.startsWith("LVDS-"))
    readonly property bool hasExternal: monitors.some(monitor => !monitor.name.startsWith("eDP-") && !monitor.name.startsWith("LVDS-"))
    readonly property var actions: [
        { action: "mirror", icon: "flip", label: "Mirror" },
        { action: "laptop", icon: "laptop", label: "Laptop" },
        { action: "external", icon: "desktop_windows", label: "External" },
        { action: "reset", icon: "restart_alt", label: "Reset" }
    ]
    property var pendingCommand: []

    function quoteLua(value) {
        return `"${String(value).replace(/\\/g, "\\\\").replace(/"/g, '\\"')}"`;
    }

    function modeFor(monitor, width, height, refreshRate) {
        const prefix = `${width}x${height}@`;
        const requested = `${prefix}${Number(refreshRate).toFixed(2)}Hz`;
        return monitor.availableModes?.includes(requested)
            ? requested
            : (monitor.availableModes?.find(mode => mode.startsWith(prefix)) ?? "preferred");
    }

    function monitorRule(monitor, disabled, mirror, mode = "preferred", scale = "1") {
        let rule = `{ output = ${quoteLua(monitor.name)}, mode = ${quoteLua(mode)}, position = "auto", scale = ${quoteLua(scale)}, disabled = ${disabled ? "true" : "false"}`;
        if (mirror)
            rule += `, mirror = ${quoteLua(mirror)}`;
        return `${rule} }`;
    }

    function applyAction(action) {
        const outputs = monitors;
        if (outputs.length === 0)
            return;

        if (action === "reset") {
            commandProc.command = ["hyprctl", "reload"];
            commandProc.running = true;
            return;
        }

        if (action === "mirror" && outputs.length < 2) {
            notifyProc.command = ["notify-send", "Displays", "Connect a second display first"];
            notifyProc.running = true;
            return;
        }

        if (action === "laptop" && !root.hasLaptop || action === "external" && !root.hasExternal) {
            notifyProc.command = ["notify-send", "Displays", "That display mode is not available"];
            notifyProc.running = true;
            return;
        }

        const laptop = outputs.find(monitor => monitor.name.startsWith("eDP-") || monitor.name.startsWith("LVDS-"));
        // Keep the laptop as the mirror source. Hyprland gives the mirror
        // target the source geometry; using a focused external display here
        // can make the laptop inherit its lower or unusual resolution.
        const source = laptop ?? outputs.find(monitor => monitor.focused) ?? outputs[0];
        let rules = [];

        if (action === "mirror") {
            const target = outputs.find(monitor => monitor.name !== source.name);
            const sourceMode = modeFor(source, source.width, source.height, source.refreshRate);
            const sourceSize = `${source.width}x${source.height}@`;
            const targetMode = target.availableModes?.find(mode => mode.startsWith(sourceSize));
            if (!targetMode) {
                notifyProc.command = ["notify-send", "Displays", "No compatible mirror resolution"];
                notifyProc.running = true;
                return;
            }
            rules = [
                monitorRule(source, false, null, sourceMode, "1"),
                // Keep the output at 1:1. `auto` can apply the target's DPI
                // and make a mirrored desktop look aggressively zoomed in.
                monitorRule(target, false, source.name, targetMode, "1")
            ];
        } else if (action === "laptop" || action === "external") {
            const enabledRules = [];
            const disabledRules = [];
            outputs.forEach(monitor => {
                const isLaptop = laptop ? monitor.name === laptop.name : false;
                const enabled = action === "laptop" ? isLaptop : !isLaptop;
                const rule = monitorRule(monitor, !enabled, null);
                // When switching to an external display, enable it first.
                // Disabling the screen hosting this popup first can destroy
                // its layer surface while the runtime command is executing.
                (enabled ? enabledRules : disabledRules).push(rule);
            });
            rules = enabledRules.concat(disabledRules);
        } else {
            outputs.forEach(monitor => rules.push(monitorRule(monitor, false, null)));
        }

        pendingCommand = ["hyprctl", "eval", rules.map(rule => `hl.monitor(${rule})`).join("; ")];
        if (action === "external") {
            const target = outputs.find(monitor => laptop ? monitor.name !== laptop.name : true);
            if (source.focused) {
                // Move focus away from the laptop before disabling its output.
                // `hyprctl dispatch` is parsed as Lua in this config, so use
                // the native dispatcher object rather than a raw CLI string.
                focusProc.command = ["hyprctl", "eval", `hl.dispatch(hl.dsp.focus({ monitor = ${quoteLua(target.name)} }))`];
                focusProc.running = true;
            } else {
                commandProc.command = pendingCommand;
                commandProc.running = true;
            }
        } else {
            commandProc.command = pendingCommand;
            commandProc.running = true;
        }
    }

    function refreshAfterAction() {
        refreshTimer.restart();
    }

    Timer {
        id: refreshTimer
        interval: 350
        onTriggered: HyprlandData.updateMonitors()
    }

    Process {
        id: commandProc
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                notifyProc.command = ["notify-send", "Displays", "Could not apply display mode"];
                notifyProc.running = true;
            }
            refreshAfterAction();
        }
    }

    Process {
        id: focusProc
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) {
                commandProc.command = root.pendingCommand;
                commandProc.running = true;
            } else {
                notifyProc.command = ["notify-send", "Displays", "Could not focus the external display"];
                notifyProc.running = true;
            }
        }
    }

    Process {
        id: notifyProc
    }

    Loader {
        active: GlobalStates.displayControlOpen
        sourceComponent: PanelWindow {
            id: panelWindow
            screen: Quickshell.screens.find(screen => Hyprland.monitorFor(screen)?.id === Hyprland.focusedMonitor?.id) ?? Quickshell.screens[0]
            visible: true
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "quickshell:displayControl"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            Rectangle {
                anchors.fill: parent
                color: Appearance.colors.colLayer0
                opacity: 0.28
            }

            Component.onCompleted: GlobalFocusGrab.addDismissable(panelWindow)
            Component.onDestruction: GlobalFocusGrab.removeDismissable(panelWindow)

            Connections {
                target: GlobalFocusGrab
                function onDismissed() {
                    GlobalStates.displayControlOpen = false;
                }
            }

            Rectangle {
                id: card
                anchors.centerIn: parent
                width: controls.implicitWidth + 28
                height: controls.implicitHeight + 28
                radius: Appearance.rounding.large
                color: "#1c1c1c"
                border.color: Appearance.colors.colLayer3Border
                border.width: 1

                ColumnLayout {
                    id: controls
                    anchors.centerIn: parent
                    spacing: 12

                    RowLayout {
                        spacing: 6

                        Repeater {
                            model: root.monitors
                            delegate: RowLayout {
                                required property var modelData
                                spacing: 4

                                Rectangle {
                                    implicitWidth: 7
                                    implicitHeight: 7
                                    radius: 4
                                    color: modelData.disabled ? Appearance.colors.colSubtext : Appearance.colors.colPrimary
                                }
                                StyledText {
                                    text: modelData.name
                                    color: modelData.disabled ? Appearance.colors.colSubtext : Appearance.colors.colOnLayer2
                                    font.pixelSize: Appearance.font.pixelSize.small
                                }
                            }
                        }
                    }

                    RowLayout {
                        spacing: 6

                        Repeater {
                            model: root.actions
                            delegate: RippleButton {
                                required property var modelData
                                implicitWidth: 64
                                implicitHeight: 54
                                buttonRadius: Appearance.rounding.small
                                enabled: (modelData.action !== "mirror" || root.monitors.length > 1)
                                    && (modelData.action !== "laptop" || root.hasLaptop)
                                    && (modelData.action !== "external" || root.hasExternal)
                                onClicked: {
                                    root.applyAction(modelData.action)
                                    GlobalStates.displayControlOpen = false
                                }

                                contentItem: ColumnLayout {
                                    spacing: 1
                                    anchors.centerIn: parent

                                    MaterialSymbol {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: modelData.icon
                                        iconSize: 20
                                        color: parent.parent.enabled ? Appearance.colors.colOnLayer3 : Appearance.colors.colSubtext
                                    }
                                    StyledText {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: modelData.label
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        color: parent.parent.enabled ? Appearance.colors.colOnLayer3 : Appearance.colors.colSubtext
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    IpcHandler {
        target: "displayControl"

        function toggle(): void {
            GlobalStates.displayControlOpen = !GlobalStates.displayControlOpen;
        }

        function close(): void {
            GlobalStates.displayControlOpen = false;
        }
    }

    GlobalShortcut {
        name: "displayControlToggle"
        description: "Toggle display controls"
        onPressed: GlobalStates.displayControlOpen = !GlobalStates.displayControlOpen
    }
}
