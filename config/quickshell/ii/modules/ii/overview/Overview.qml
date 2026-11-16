import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import Qt.labs.synchronizer
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: overviewScope
    property bool dontAutoCancelSearch: false

    PanelWindow {
        id: panelWindow
        property string searchingText: ""
        readonly property HyprlandMonitor monitor: Hyprland.monitorFor(panelWindow.screen)
        property bool monitorIsFocused: (Hyprland.focusedMonitor?.id == monitor?.id)
        // Drop-down panel aligned with the bar's centered cluster.
        readonly property real panelWidth: GlobalStates.barMiddleSectionWidth > 0 ? GlobalStates.barMiddleSectionWidth : 640
        readonly property real panelRadius: Appearance.rounding.large + 10
        // Radius of the concave joints between the bar and the panel.
        readonly property real jointRadius: Appearance.rounding.large
        // 0 = tucked into the bar, 1 = fully extended. Extension waits for the
        // surface to be mapped so the first frames are not lost to window setup.
        readonly property real revealTarget: (GlobalStates.overviewOpen && backingWindowVisible) ? 1 : 0
        property real reveal: 0
        property real revealVelocity: 0
        readonly property real shown: Math.max(0, Math.min(1, reveal))
        // Staggered entrance: block `index` starts a little after the previous
        // one. Pure functions of `reveal`, so they follow the spring both ways.
        function stage(index) {
            return Math.max(0, Math.min(1, (reveal - 0.2 - index * 0.1) / 0.45));
        }
        function stageOffset(index) {
            return -14 * (1 - stage(index));
        }
        // Critically damped spring stepped once per rendered frame. Unlike an
        // easing curve it keeps its velocity when the target flips mid-flight,
        // so rapid toggling reverses smoothly instead of restarting. (Qt's
        // SpringAnimation integrates in 16 ms steps, i.e. ~60 Hz on any display.)
        readonly property real revealStiffness: 18 // rad/s; ~99% settled in 370 ms
        function stepReveal(dt) {
            const factor = Appearance.animationFactor;
            if (!(Number.isFinite(factor) && factor > 0)) { // reduce motion
                revealVelocity = 0;
                reveal = revealTarget;
                return;
            }
            const omega = revealStiffness / factor;
            let x = reveal;
            let v = revealVelocity;
            // Cap the step so a dropped frame resumes the motion instead of jumping.
            let remaining = Math.min(dt, 0.025);
            while (remaining > 0) {
                const h = Math.min(0.002, remaining);
                v += (-omega * omega * (x - revealTarget) - 2 * omega * v) * h;
                x += v * h;
                remaining -= h;
            }
            if (Math.abs(x - revealTarget) < 0.0005 && Math.abs(v) < 0.01) {
                x = revealTarget;
                v = 0;
            }
            revealVelocity = v;
            reveal = x;
        }
        FrameAnimation {
            running: panelWindow.reveal !== panelWindow.revealTarget
            onTriggered: panelWindow.stepReveal(frameTime)
        }
        // Stay mapped until the retract animation finishes.
        visible: GlobalStates.overviewOpen || reveal > 0

        WlrLayershell.namespace: "quickshell:overview"
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.keyboardFocus: GlobalStates.overviewOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        color: "transparent"

        mask: Region {
            item: GlobalStates.overviewOpen ? panelHitbox : null
        }

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        Connections {
            target: GlobalStates
            function onOverviewOpenChanged() {
                if (!GlobalStates.overviewOpen) {
                    searchWidget.disableExpandAnimation();
                    overviewScope.dontAutoCancelSearch = false;
                    GlobalFocusGrab.dismiss();
                } else {
                    if (!overviewScope.dontAutoCancelSearch) {
                        searchWidget.cancelSearch();
                    }
                    GlobalFocusGrab.addDismissable(panelWindow);
                }
            }
        }

        Connections {
            target: GlobalFocusGrab
            function onDismissed() {
                GlobalStates.overviewOpen = false;
            }
        }
        implicitWidth: panel.width
        implicitHeight: panel.fullHeight

        function setSearchingText(text) {
            searchWidget.setSearchingText(text);
            searchWidget.focusFirstItem();
        }

        Item { // Visible part of the panel; input mask and joint anchor
            id: panelHitbox
            anchors {
                horizontalCenter: parent.horizontalCenter
                top: parent.top
            }
            width: panelWindow.panelWidth
            height: panel.fullHeight * panelWindow.shown
        }

        // Edge light, soft halo: below the panel so it only leaks outward.
        PanelEdgeLight {
            soft: true
            x: panelHitbox.x - edgeOffset
            jointRadius: panelWindow.jointRadius
            cornerRadius: panelWindow.panelRadius
            fullHeight: panel.fullHeight
            visibleHeight: panelHitbox.height
            opacity: panelWindow.shown
        }
        PanelEdgeLight {
            soft: true
            mirrored: true
            x: panelHitbox.x + panelHitbox.width - bleed
            jointRadius: panelWindow.jointRadius
            cornerRadius: panelWindow.panelRadius
            fullHeight: panel.fullHeight
            visibleHeight: panelHitbox.height
            opacity: panelWindow.shown
        }

        // Concave joints so the panel reads as extruded from the bar.
        RoundCorner {
            anchors.top: panelHitbox.top
            anchors.right: panelHitbox.left
            implicitSize: Math.min(panelWindow.jointRadius, panelHitbox.height)
            corner: RoundCorner.CornerEnum.TopRight
            color: panelBackground.color
        }
        RoundCorner {
            anchors.top: panelHitbox.top
            anchors.left: panelHitbox.right
            implicitSize: Math.min(panelWindow.jointRadius, panelHitbox.height)
            corner: RoundCorner.CornerEnum.TopLeft
            color: panelBackground.color
        }

        Item {
            id: panel
            property real fullHeight: columnLayout.implicitHeight
            // Only animate content-driven resizes (grid <-> results); while the
            // panel is extending, `reveal` alone drives the motion.
            Behavior on fullHeight {
                enabled: panelWindow.reveal === 1
                animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
            }
            anchors.horizontalCenter: parent.horizontalCenter
            width: panelWindow.panelWidth
            height: fullHeight
            clip: true
            // Fixed-size item slid out from above the window's top edge (which
            // sits right under the bar): the animation is a pure translation,
            // with no per-frame resize, clip or relayout.
            y: -fullHeight * (1 - panelWindow.shown)

            Rectangle {
                id: panelBackground
                anchors.fill: parent
                // Same surface as the bar, so both read as one piece.
                color: Appearance.colors.colLayer0
                bottomLeftRadius: panelWindow.panelRadius
                bottomRightRadius: panelWindow.panelRadius
            }

            Column {
                id: columnLayout
                // Pinned to the top: while `fullHeight` animates toward a new
                // content height (results appearing as you type), the search
                // field must not move. The panel clips whatever does not fit yet.
                anchors {
                    horizontalCenter: parent.horizontalCenter
                    top: parent.top
                }
                width: parent.width

                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Escape) {
                        GlobalStates.overviewOpen = false;
                    }
                }

                SearchWidget {
                    id: searchWidget
                    embedded: true
                    embeddedWidth: panelWindow.panelWidth
                    opacity: panelWindow.stage(0)
                    transform: Translate { y: panelWindow.stageOffset(0) }
                    Synchronizer on searchingText {
                        property alias source: panelWindow.searchingText
                    }
                }

                Item { // Idle content: active workspace + "now" column
                    id: body
                    readonly property real margin: 12
                    readonly property real gap: 10
                    readonly property real sideWidth: 220
                    readonly property real mainWidth: width - margin * 2 - gap - sideWidth
                    readonly property real infoHeight: 104
                    visible: panelWindow.searchingText == ""
                    width: parent.width
                    height: Math.max(mainColumn.implicitHeight, 200) + margin

                    Column {
                        id: mainColumn
                        x: body.margin
                        width: body.mainWidth
                        spacing: 8

                        Loader {
                            id: overviewLoader
                            // Kept loaded while closed: building it on open cost
                            // ~100 ms of dropped frames at the start of the animation.
                            // Waits for monitor data so it is laid out once.
                            active: (Config?.options.overview.enable ?? true) && HyprlandData.monitors.length > 0
                            opacity: panelWindow.stage(1)
                            transform: Translate { y: panelWindow.stageOffset(1) }
                            // Above the strip, so a dragged window stays visible over it.
                            z: 1
                            sourceComponent: OverviewWidget {
                                screen: panelWindow.screen
                                embedded: true
                                rows: 1
                                columns: 1
                                padding: 0
                                targetWidth: body.mainWidth
                                liveCapture: panelWindow.reveal === 1
                            }
                        }

                        PanelWorkspaceStrip {
                            screen: panelWindow.screen
                            dragHost: overviewLoader.item
                            // A dragged mini icon must paint above the preview.
                            z: iconDragging ? 2 : 0
                            width: body.mainWidth
                            opacity: panelWindow.stage(2)
                            transform: Translate { y: panelWindow.stageOffset(2) }
                        }
                    }

                    PanelMediaCard {
                        id: mediaCard
                        x: body.margin + body.mainWidth + body.gap
                        width: body.sideWidth
                        height: body.height - body.margin - 8 - body.infoHeight
                        live: panelWindow.visible
                        opacity: panelWindow.stage(2)
                        transform: Translate { y: panelWindow.stageOffset(2) }
                    }

                    PanelInfoCard {
                        x: mediaCard.x
                        y: mediaCard.height + 8
                        width: body.sideWidth
                        height: body.infoHeight
                        opacity: panelWindow.stage(3)
                        transform: Translate { y: panelWindow.stageOffset(3) }
                    }
                }
            }
        }

        // Edge light, crisp rim: above the panel, exactly on its outline.
        PanelEdgeLight {
            x: panelHitbox.x - edgeOffset
            jointRadius: panelWindow.jointRadius
            cornerRadius: panelWindow.panelRadius
            fullHeight: panel.fullHeight
            visibleHeight: panelHitbox.height
            opacity: panelWindow.shown
        }
        PanelEdgeLight {
            mirrored: true
            x: panelHitbox.x + panelHitbox.width - bleed
            jointRadius: panelWindow.jointRadius
            cornerRadius: panelWindow.panelRadius
            fullHeight: panel.fullHeight
            visibleHeight: panelHitbox.height
            opacity: panelWindow.shown
        }
    }

    function toggleClipboard() {
        if (GlobalStates.overviewOpen && overviewScope.dontAutoCancelSearch) {
            GlobalStates.overviewOpen = false;
            return;
        }
        overviewScope.dontAutoCancelSearch = true;
        panelWindow.setSearchingText(Config.options.search.prefix.clipboard);
        GlobalStates.overviewOpen = true;
    }

    function toggleEmojis() {
        if (GlobalStates.overviewOpen && overviewScope.dontAutoCancelSearch) {
            GlobalStates.overviewOpen = false;
            return;
        }
        overviewScope.dontAutoCancelSearch = true;
        panelWindow.setSearchingText(Config.options.search.prefix.emojis);
        GlobalStates.overviewOpen = true;
    }

    IpcHandler {
        target: "search"

        function toggle() {
            GlobalStates.overviewOpen = !GlobalStates.overviewOpen;
        }
        function workspacesToggle() {
            GlobalStates.overviewOpen = !GlobalStates.overviewOpen;
        }
        function close() {
            GlobalStates.overviewOpen = false;
        }
        function open() {
            GlobalStates.overviewOpen = true;
        }
        function toggleReleaseInterrupt() {
            GlobalStates.superReleaseMightTrigger = false;
        }
        function clipboardToggle() {
            overviewScope.toggleClipboard();
        }
    }

    GlobalShortcut {
        name: "searchToggle"
        description: "Toggles search on press"

        onPressed: {
            GlobalStates.overviewOpen = !GlobalStates.overviewOpen;
        }
    }
    GlobalShortcut {
        name: "overviewWorkspacesClose"
        description: "Closes overview on press"

        onPressed: {
            GlobalStates.overviewOpen = false;
        }
    }
    GlobalShortcut {
        name: "overviewWorkspacesToggle"
        description: "Toggles overview on press"

        onPressed: {
            GlobalStates.overviewOpen = !GlobalStates.overviewOpen;
        }
    }
    GlobalShortcut {
        name: "searchToggleRelease"
        description: "Toggles search on release"

        onPressed: {
            GlobalStates.superReleaseMightTrigger = true;
        }

        onReleased: {
            if (!GlobalStates.superReleaseMightTrigger) {
                GlobalStates.superReleaseMightTrigger = true;
                return;
            }
            GlobalStates.overviewOpen = !GlobalStates.overviewOpen;
        }
    }
    GlobalShortcut {
        name: "searchToggleReleaseInterrupt"
        description: "Interrupts possibility of search being toggled on release. " + "This is necessary because GlobalShortcut.onReleased in quickshell triggers whether or not you press something else while holding the key. " + "To make sure this works consistently, use binditn = MODKEYS, catchall in an automatically triggered submap that includes everything."

        onPressed: {
            GlobalStates.superReleaseMightTrigger = false;
        }
    }
    GlobalShortcut {
        name: "overviewClipboardToggle"
        description: "Toggle clipboard query on overview widget"

        onPressed: {
            overviewScope.toggleClipboard();
        }
    }

    GlobalShortcut {
        name: "overviewEmojiToggle"
        description: "Toggle emoji query on overview widget"

        onPressed: {
            overviewScope.toggleEmojis();
        }
    }
}
