pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Widgets
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

// One tile per workspace of the current group: click to jump there. Occupied
// workspaces show icons of their windows; an icon can be dragged onto another
// tile to move that window, and so can a window from the preview (dragHost).
Row {
    id: root
    required property var screen
    // OverviewWidget whose windows can be dropped on a tile to move them
    // there. It performs the move on release, using draggingTargetWorkspace.
    property var dragHost: null
    readonly property HyprlandMonitor monitor: Hyprland.monitorFor(screen)
    readonly property int count: Math.max(1, Config.options?.bar.workspaces.shown ?? 9)
    // Clamp to avoid lock-screen temp workspace ids leaking into the UI.
    readonly property int activeId: Math.max(1, Math.min(100, monitor?.activeWorkspace?.id ?? 1))
    readonly property int group: Math.floor((activeId - 1) / count)
    readonly property real tileWidth: (width - spacing * (count - 1)) / count
    readonly property int iconsPerTile: 2
    // workspace id -> [{ address, windowClass, title }]; built once per update.
    readonly property var windowsByWorkspace: {
        const map = {};
        for (const win of HyprlandData.windowList) {
            const id = win?.workspace?.id;
            if (id === undefined)
                continue;
            if (map[id] === undefined)
                map[id] = [];
            map[id].push({ address: win.address, windowClass: win.class, title: win.title });
        }
        return map;
    }
    // True while one of the mini icons is being dragged.
    property bool iconDragging: false

    function focusWorkspace(id) {
        GlobalStates.overviewOpen = false;
        Hyprland.dispatch(`hl.dsp.focus({ workspace = ${id} })`);
    }

    spacing: 4
    height: 40

    Repeater {
        model: root.count
        Rectangle {
            id: tile
            required property int index
            readonly property int workspaceId: root.group * root.count + index + 1
            readonly property bool active: workspaceId === root.activeId
            readonly property var windows: root.windowsByWorkspace[workspaceId] ?? []
            readonly property bool occupied: windows.length > 0
            property bool dropHovered: false
            property bool holdsDrag: false

            width: root.tileWidth
            height: root.height
            // The tile owning the dragged icon paints above its siblings.
            z: holdsDrag ? 1 : 0
            radius: Appearance.rounding.small
            color: dropHovered ? Appearance.colors.colPrimary
                : active ? Appearance.colors.colSecondaryContainer
                : tileArea.containsMouse ? Appearance.colors.colLayer1Hover : Appearance.colors.colLayer1
            scale: dropHovered ? 1.08 : 1
            Behavior on scale {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }

            MouseArea { // Below the icons: click anywhere else on the tile
                id: tileArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.focusWorkspace(tile.workspaceId)
            }

            Column {
                anchors.centerIn: parent
                spacing: 1

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: tile.occupied
                    spacing: 2
                    Repeater {
                        model: tile.windows.slice(0, root.iconsPerTile)
                        Item { // Fixed slot; the icon inside is what moves
                            id: slot
                            required property var modelData
                            width: 16
                            height: 16

                            WindowAppIcon {
                                id: dragIcon
                                // Read by the drop target.
                                readonly property bool stripIcon: true
                                readonly property string windowAddress: slot.modelData.address
                                readonly property int fromWorkspace: tile.workspaceId
                                width: 16
                                height: 16
                                windowClass: slot.modelData.windowClass ?? ""
                                title: slot.modelData.title ?? ""
                                showBadge: false
                                scale: iconArea.drag.active ? 1.5 : 1
                                Behavior on scale {
                                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                                }
                                Drag.active: iconArea.drag.active
                                Drag.source: dragIcon
                                Drag.hotSpot.x: width / 2
                                Drag.hotSpot.y: height / 2

                                MouseArea {
                                    id: iconArea
                                    anchors.fill: parent
                                    cursorShape: drag.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                                    drag.target: dragIcon
                                    drag.threshold: 4
                                    drag.onActiveChanged: {
                                        tile.holdsDrag = drag.active;
                                        root.iconDragging = drag.active;
                                    }
                                    onClicked: root.focusWorkspace(tile.workspaceId)
                                    onReleased: {
                                        if (drag.active)
                                            dragIcon.Drag.drop();
                                        dragIcon.x = 0;
                                        dragIcon.y = 0;
                                    }
                                }
                            }
                        }
                    }
                }

                StyledText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: tile.windows.length > root.iconsPerTile
                        ? `${tile.workspaceId} · +${tile.windows.length - root.iconsPerTile}` : tile.workspaceId
                    font.pixelSize: tile.occupied ? Appearance.font.pixelSize.smallest : Appearance.font.pixelSize.small
                    font.weight: tile.active ? Font.DemiBold : Font.Normal
                    color: tile.dropHovered ? Appearance.colors.colOnPrimary
                        : tile.active ? Appearance.m3colors.m3onSecondaryContainer
                        : tile.occupied ? Appearance.colors.colOnLayer1 : Appearance.colors.colSubtext
                }
            }

            DropArea {
                anchors.fill: parent
                onEntered: drag => {
                    if (drag.source?.stripIcon) {
                        tile.dropHovered = drag.source.fromWorkspace !== tile.workspaceId;
                        return;
                    }
                    // A window dragged from the preview: the host moves it on release.
                    if (root.dragHost === null)
                        return;
                    root.dragHost.draggingTargetWorkspace = tile.workspaceId;
                    tile.dropHovered = root.dragHost.draggingFromWorkspace !== tile.workspaceId;
                }
                onExited: {
                    tile.dropHovered = false;
                    if (root.dragHost !== null && root.dragHost.draggingTargetWorkspace === tile.workspaceId)
                        root.dragHost.draggingTargetWorkspace = -1;
                }
                onDropped: drop => {
                    tile.dropHovered = false;
                    const source = drop.source;
                    if (!source?.stripIcon || source.fromWorkspace === tile.workspaceId)
                        return;
                    Hyprland.dispatch(`hl.dsp.window.move({ workspace = ${tile.workspaceId}, follow = false, window = "address:${source.windowAddress}" })`);
                }
            }
        }
    }
}
