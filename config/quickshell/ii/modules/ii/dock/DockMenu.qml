pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell

// Right-click menu of a dock entry. Shown while `button` is set; asks its
// owner to clear it through `dismissed`.
PopupWindow {
    id: root
    property Item button: null
    // Window coordinates of the point the menu rises from.
    property real anchorX: 0
    property real anchorY: 0
    readonly property real margin: Appearance.sizes.elevationMargin
    signal dismissed

    function run(action) {
        action();
        root.dismissed();
    }

    visible: button !== null
    onVisibleChanged: {
        if (visible)
            anchor.updateAnchor();
    }
    // A right click on another entry moves the open menu.
    onAnchorXChanged: {
        if (visible)
            anchor.updateAnchor();
    }
    color: "transparent"
    // anchor.window is set by the owner.
    anchor {
        rect.x: root.anchorX
        rect.y: root.anchorY
        rect.width: 1
        rect.height: 1
        edges: Edges.Top
        gravity: Edges.Top
        adjustment: PopupAdjustment.SlideX
    }
    implicitWidth: menuBackground.implicitWidth + margin * 2
    implicitHeight: menuBackground.implicitHeight + margin * 2

    StyledRectangularShadow {
        target: menuBackground
    }

    Rectangle {
        id: menuBackground
        readonly property real padding: 4
        anchors.centerIn: parent
        // Same surface as the dock.
        color: Appearance.colors.colLayer0
        radius: Appearance.rounding.large
        implicitWidth: Math.max(180, menuColumn.implicitWidth + padding * 2)
        implicitHeight: menuColumn.implicitHeight + padding * 2

        ColumnLayout {
            id: menuColumn
            anchors {
                fill: parent
                margins: menuBackground.padding
            }
            spacing: 0

            DockMenuItem {
                // A split terminal entry stands for a program, not a launcher.
                visible: (root.button?.program ?? "") === ""
                buttonRadius: menuBackground.radius - menuBackground.padding
                symbol: root.button?.pinned ? "keep_off" : "keep"
                label: root.button?.pinned ? Translation.tr("Unpin") : Translation.tr("Pin")
                onClicked: root.run(() => TaskbarApps.togglePin(root.button.windowClass))
            }
            DockMenuItem {
                visible: root.button?.desktopEntry ? true : false
                buttonRadius: menuBackground.radius - menuBackground.padding
                symbol: "add"
                label: Translation.tr("New window")
                onClicked: root.run(() => root.button.launch())
            }
            DockMenuItem {
                visible: root.button?.awayToplevel ? true : false
                buttonRadius: menuBackground.radius - menuBackground.padding
                symbol: "move_down"
                label: Translation.tr("Move here")
                onClicked: {
                    const button = root.button;
                    const toplevel = button.awayToplevel;
                    root.run(() => button.focusWindow(toplevel, true));
                }
            }
            DockMenuItem {
                visible: (root.button?.toplevels.length ?? 0) > 0
                buttonRadius: menuBackground.radius - menuBackground.padding
                symbol: "close"
                label: (root.button?.toplevels.length ?? 0) > 1 ? Translation.tr("Close window") : Translation.tr("Close")
                onClicked: {
                    const button = root.button;
                    root.run(() => button.closeWindow(button.mostRecent(button.toplevels)));
                }
            }
        }
    }
}
