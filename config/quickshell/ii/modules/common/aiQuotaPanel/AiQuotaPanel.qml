import qs
import qs.modules.common
import qs.services
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

// AI quota overview panel. It reuses the authenticator's reveal behavior
// (grow from the bar band, single monitor per presentation, drag/Esc to close)
// but shows a header-less six-column layout.
Scope {
    id: root

    property real revealProgress: 0
    property bool panelActive: false
    property bool forcingClose: false
    property bool gestureActive: false
    property real gestureStartProgress: 0
    readonly property var selectedScreen: Quickshell.screens.find(screen => screen.name === GlobalStates.aiQuotaPanelScreenName) ?? null

    Binding {
        target: GlobalStates
        property: "aiQuotaPanelPresented"
        value: root.panelActive
    }

    function closeImmediately(): void {
        root.forcingClose = true;
        root.gestureActive = false;
        revealAnimation.stop();
        GlobalStates.aiQuotaPanelOpen = false;
        root.panelActive = false;
        root.revealProgress = 0;
        GlobalStates.aiQuotaPanelScreenName = "";
        root.forcingClose = false;
    }

    function synchronize(): void {
        if (root.forcingClose) return;
        root.gestureActive = false;
        if (GlobalStates.aiQuotaPanelOpen) {
            // Also support callers that only set the open flag directly.
            if (!GlobalStates.aiQuotaPanelScreenName) GlobalStates.openAiQuotaPanel("");
            if (GlobalStates.screenLocked || !root.selectedScreen) {
                root.closeImmediately();
                return;
            }
            root.panelActive = true;
        } else if (!root.panelActive) {
            return;
        }

        revealAnimation.stop();
        revealAnimation.from = root.revealProgress;
        revealAnimation.to = GlobalStates.aiQuotaPanelOpen ? 1 : 0;
        const motion = GlobalStates.aiQuotaPanelOpen ? Appearance.animation.elementMoveEnter : Appearance.animation.elementMoveExit;
        // Full-screen travel needs a softer start/finish than a small popup.
        const fullDuration = Math.max(GlobalStates.aiQuotaPanelOpen ? 520 : 420, motion.duration);
        revealAnimation.duration = Math.max(160, fullDuration * Math.abs(revealAnimation.to - root.revealProgress));
        revealAnimation.easing.type = Easing.InOutCubic;
        revealAnimation.start();
    }

    function beginDrag(): void {
        if (!root.panelActive || !GlobalStates.aiQuotaPanelOpen || root.forcingClose) return;
        revealAnimation.stop();
        root.gestureStartProgress = root.revealProgress;
        root.gestureActive = true;
    }

    function moveDrag(distance: real): void {
        if (!root.gestureActive) return;
        const travel = Math.max(1, root.selectedScreen.height - Appearance.sizes.barHeight);
        root.revealProgress = Math.max(0, root.gestureStartProgress - distance / travel);
    }

    function finishDrag(dismiss: bool): void {
        if (!root.gestureActive) return;
        root.gestureActive = false;
        if (dismiss) GlobalStates.aiQuotaPanelOpen = false;
        else root.synchronize();
    }

    onSelectedScreenChanged: {
        if (root.panelActive && !root.selectedScreen) root.closeImmediately();
    }
    Component.onCompleted: root.synchronize()

    Connections {
        target: GlobalStates
        function onAiQuotaPanelOpenChanged() {
            root.synchronize();
        }
        function onScreenLockedChanged() {
            if (GlobalStates.screenLocked && root.panelActive) root.closeImmediately();
        }
    }

    NumberAnimation {
        id: revealAnimation
        target: root
        property: "revealProgress"
        alwaysRunToEnd: false
        onFinished: {
            if (!GlobalStates.aiQuotaPanelOpen) {
                root.panelActive = false;
                GlobalStates.aiQuotaPanelScreenName = "";
            }
        }
    }

    Loader {
        active: root.panelActive
        sourceComponent: PanelWindow {
            id: panel
            screen: root.selectedScreen
            // Keep the dialog/job alive but release exclusive keyboard focus for login.
            visible: !AiQuotaUsage.overlayCollapsed && !AiQuotaUsage.externalBrowserSetup
                && (!AiQuotaUsage.authorizationActive || AiQuotaUsage.authorizationUiVisible)
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "quickshell:ai-quota-panel"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            anchors { top: true; bottom: true; left: true; right: true }

            AiQuotaPanelCurtain {
                anchors.fill: parent
                revealProgress: root.revealProgress
                onCloseRequested: GlobalStates.aiQuotaPanelOpen = false
                onDragStarted: root.beginDrag()
                onDragMoved: distance => root.moveDrag(distance)
                onDragFinished: dismiss => root.finishDrag(dismiss)
            }
        }
    }

    IpcHandler {
        target: "aiQuotaPanel"
        function toggle(): void { GlobalStates.toggleAiQuotaPanel(); }
        function close(): void { GlobalStates.aiQuotaPanelOpen = false; }
        function connectProvider(provider: string): void {
            AiQuotaUsage.requestConnection(provider);
            GlobalStates.openAiQuotaPanel("");
        }
    }
}
