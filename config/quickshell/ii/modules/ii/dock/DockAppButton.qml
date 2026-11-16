pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import Qt5Compat.GraphicalEffects
import QtQuick
import Quickshell
import Quickshell.Hyprland

RippleButton {
    id: root
    property var entry
    property var appListRoot
    property real size: 48
    readonly property real iconSize: Math.round(size * 0.62)
    readonly property real dotSize: Math.max(3, Math.round(size * 0.085))

    readonly property var toplevels: entry?.toplevels ?? []
    readonly property bool isSeparator: entry?.appId === "SEPARATOR"
    readonly property string windowClass: entry?.windowClass ?? ""
    // TUI program of a split terminal entry, "" for plain apps.
    readonly property string program: entry?.program ?? ""
    readonly property bool pinned: entry?.pinned ?? false
    property var desktopEntry: DesktopEntries.heuristicLookup(windowClass)

    // Names for WindowIcons.titleApps' marks, keyed by their icon id.
    readonly property var programNames: ({
            "claude": "Claude Code",
            "openai": "Codex",
            "cursor": "Cursor Agent",
            "opencode": "OpenCode"
        })
    readonly property string displayName: {
        if (program.length > 0)
            return programNames[program] ?? DesktopEntries.heuristicLookup(program)?.name ?? program;
        return desktopEntry?.name ?? windowClass;
    }

    // Special workspaces that only park windows out of sight. Their windows
    // are brought to the active workspace before focusing, so the dock never
    // opens them as an overlay. Other special workspaces (the scratchpad) are
    // overlays on purpose and are left alone.
    readonly property var parkingWorkspaces: ["special:minimized", "special:grok-bot"]

    readonly property var focusedToplevel: toplevels.find(t => t.activated) ?? null
    // Most recently used window not on the active workspace, for "Move here".
    readonly property var awayToplevel: mostRecent(toplevels.filter(t => !isHere(t)))
    // At most four dots; the focused window always keeps its own.
    readonly property var dotToplevels: {
        const shown = Array.from(toplevels).slice(0, 4);
        if (focusedToplevel && !shown.includes(focusedToplevel))
            shown[shown.length - 1] = focusedToplevel;
        return shown;
    }

    function clientOf(toplevel) {
        return HyprlandData.clientForToplevel(toplevel);
    }
    // Hyprland addresses end up inside a Lua dispatch string.
    function addressOf(toplevel) {
        const address = String(clientOf(toplevel)?.address ?? "");
        return /^0x[0-9a-fA-F]+$/.test(address) ? address : "";
    }
    function isHere(toplevel) {
        const workspace = clientOf(toplevel)?.workspace;
        const active = HyprlandData.activeWorkspace;
        return !workspace || !active || workspace.id === active.id;
    }
    // Hyprland focus history: focusHistoryID 0 is the focused window, higher
    // is older.
    function mostRecent(candidates) {
        let best = null;
        let bestId = Infinity;
        for (const toplevel of candidates) {
            const id = clientOf(toplevel)?.focusHistoryID ?? Infinity;
            if (best === null || id < bestId) {
                best = toplevel;
                bestId = id;
            }
        }
        return best;
    }

    function launch() {
        root.desktopEntry?.execute();
    }
    function moveHere(toplevel) {
        const address = addressOf(toplevel);
        const workspaceId = Number(HyprlandData.activeWorkspace?.id);
        if (address.length === 0 || !Number.isInteger(workspaceId))
            return;
        Hyprland.dispatch(`hl.dsp.window.move({ workspace = ${workspaceId}, follow = false, window = "address:${address}" })`);
    }
    function focusWindow(toplevel, bringHere = false) {
        const address = addressOf(toplevel);
        if (address.length === 0) { // Not in HyprlandData yet
            toplevel?.activate();
            return;
        }
        if (bringHere || parkingWorkspaces.includes(clientOf(toplevel)?.workspace?.name))
            moveHere(toplevel);
        Hyprland.dispatch(`hl.dsp.focus({ window = "address:${address}" })`);
    }
    // Hyprland has no minimize; parking the window on a special workspace
    // that is never shown is the closest equivalent.
    function minimize(toplevel) {
        const address = addressOf(toplevel);
        if (address.length === 0)
            return;
        Hyprland.dispatch(`hl.dsp.window.move({ workspace = "special:minimized", follow = false, window = "address:${address}" })`);
    }
    function closeWindow(toplevel) {
        toplevel?.close();
    }

    enabled: !isSeparator
    opacity: 1 // The separator is disabled but must not look dimmed
    padding: 0
    implicitWidth: isSeparator ? separatorLoader.implicitWidth : size
    implicitHeight: size
    buttonRadius: Appearance.rounding.normal

    Connections {
        target: DesktopEntries
        function onApplicationsChanged() {
            root.desktopEntry = DesktopEntries.heuristicLookup(root.windowClass);
        }
    }

    onClicked: {
        if (toplevels.length === 0) {
            launch();
            return;
        }
        const focused = root.focusedToplevel;
        if (!focused) {
            focusWindow(mostRecent(toplevels));
            return;
        }
        if (toplevels.length > 1) {
            // List order, not recency: recency would bounce between two windows.
            focusWindow(toplevels[(toplevels.indexOf(focused) + 1) % toplevels.length]);
            return;
        }
        minimize(focused);
    }

    middleClickAction: () => root.launch()
    altAction: () => root.appListRoot?.openMenu(root)

    Loader {
        id: separatorLoader
        anchors.fill: parent
        active: root.isSeparator
        sourceComponent: DockSeparator {
            lineHeight: Math.round(root.size * 0.5)
        }
    }

    // Live previews for running entries; the hover is tracked here because the
    // previews belong to the whole app list.
    Loader {
        anchors.fill: parent
        active: root.toplevels.length > 0
        sourceComponent: MouseArea {
            hoverEnabled: true
            acceptedButtons: Qt.NoButton
            onEntered: {
                root.appListRoot.lastHoveredButton = root;
                root.appListRoot.buttonHovered = true;
            }
            onExited: {
                if (root.appListRoot.lastHoveredButton === root)
                    root.appListRoot.buttonHovered = false;
            }
        }
    }

    // Name for entries without windows; running ones show it in the preview.
    PopupToolTip {
        extraVisibleCondition: !root.isSeparator && root.toplevels.length === 0 && root.appListRoot?.menuButton !== root
        text: root.displayName
    }

    contentItem: Item {
        visible: !root.isSeparator

        WindowAppIcon {
            id: appIcon
            anchors.horizontalCenter: parent.horizontalCenter
            // Nudged up to make room for the window dots.
            y: Math.round((parent.height - height) / 2 - root.size * 0.06)
            width: root.iconSize
            height: root.iconSize
            windowClass: root.windowClass
            title: root.toplevels[0]?.title ?? ""
        }

        Loader {
            active: Config.options.dock.monochromeIcons
            anchors.fill: appIcon
            sourceComponent: Item {
                Desaturate {
                    id: desaturatedIcon
                    visible: false // There's already color overlay
                    anchors.fill: parent
                    source: appIcon
                    desaturation: 0.8
                }
                ColorOverlay {
                    anchors.fill: desaturatedIcon
                    source: desaturatedIcon
                    color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.9)
                }
            }
        }

        Row {
            anchors {
                horizontalCenter: parent.horizontalCenter
                bottom: parent.bottom
                bottomMargin: Math.round(root.size * 0.08)
            }
            spacing: Math.max(2, Math.round(root.dotSize * 0.75))
            Repeater {
                model: root.dotToplevels
                delegate: Rectangle {
                    id: dot
                    required property var modelData
                    readonly property bool focused: modelData?.activated ?? false
                    implicitWidth: focused ? root.dotSize * 3 : root.dotSize
                    implicitHeight: root.dotSize
                    radius: height / 2
                    // Windows on other workspaces (or parked) read dimmer.
                    color: focused ? Appearance.colors.colPrimary : ColorUtils.transparentize(Appearance.colors.colOnLayer0, root.isHere(modelData) ? 0.3 : 0.7)
                    Behavior on implicitWidth {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }
                }
            }
        }
    }
}
