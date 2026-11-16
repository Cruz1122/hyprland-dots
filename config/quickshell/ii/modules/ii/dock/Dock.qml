import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import Quickshell.Io
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

// Bar extruded from the bottom screen edge, in the side rails' language: flush
// to the edge, concave joints where it meets it, the launcher panel's edge
// light on its outline, and a spring-driven pure translation for reveal.
Scope {
    id: root
    // "Keep open": always shown and reserves its height.
    property bool pinned: Config.options?.dock.pinnedOnStartup ?? false
    // Shown from the keyboard until toggled again, Escape or a click elsewhere.
    property bool toggledOpen: false

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: dockWindow
            required property var modelData
            screen: modelData
            visible: !GlobalStates.screenLocked

            readonly property real dockHeight: Config.options?.dock.height ?? 60
            readonly property real padding: Math.round(dockHeight * 0.1)
            readonly property real buttonSize: dockHeight - padding * 2
            readonly property real jointRadius: Appearance.rounding.large
            // Nested in the entries' rounding across the padding.
            readonly property real cornerRadius: Appearance.rounding.normal + padding
            readonly property real bodyWidth: contentRow.implicitWidth + padding * 2
            readonly property real bodyX: Math.round((width - bodyWidth) / 2)
            readonly property bool hoverToReveal: Config.options?.dock.hoverToReveal ?? true

            readonly property bool shouldShow: root.pinned || root.toggledOpen || (hoverToReveal && hoverArea.containsMouse) || dockApps.requestDockShow || !ToplevelManager.activeToplevel?.activated

            // Same critically damped spring as SideRail.stepReveal (and the
            // launcher panel): stepped once per rendered frame, keeps its
            // velocity when the target flips mid-flight. Copied rather than
            // shared; keep the two in sync.
            readonly property real revealTarget: shouldShow ? 1 : 0
            property real reveal: 0
            property real revealVelocity: 0
            readonly property real shown: Math.max(0, Math.min(1, reveal))
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
                running: dockWindow.reveal !== dockWindow.revealTarget
                onTriggered: dockWindow.stepReveal(frameTime)
            }
            // Content fades in once the body is mostly out, like the rails' stages.
            readonly property real contentStage: Math.max(0, Math.min(1, (reveal - 0.25) / 0.45))

            function syncFocusGrab() {
                if (root.toggledOpen && visible)
                    GlobalFocusGrab.addDismissable(dockWindow);
                else
                    GlobalFocusGrab.removeDismissable(dockWindow);
            }
            onVisibleChanged: syncFocusGrab()
            Connections {
                target: root
                function onToggledOpenChanged() {
                    dockWindow.syncFocusGrab();
                }
            }
            Connections {
                target: GlobalFocusGrab
                function onDismissed() {
                    root.toggledOpen = false;
                }
            }

            anchors {
                bottom: true
                left: true
                right: true
            }
            exclusiveZone: root.pinned ? dockHeight : 0
            // Room above the body for the edge light's halo.
            implicitHeight: dockHeight + rimLight.bleed
            WlrLayershell.namespace: "quickshell:dock"
            WlrLayershell.keyboardFocus: root.toggledOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
            color: "transparent"

            mask: Region {
                item: inputRegion
            }
            // The visible part of the dock, or the reveal strip at the edge.
            Item {
                id: inputRegion
                x: dockWindow.bodyX - dockWindow.jointRadius
                width: dockWindow.bodyWidth + dockWindow.jointRadius * 2
                height: Math.max(dockWindow.dockHeight * dockWindow.shown, dockWindow.hoverToReveal ? (Config.options?.dock.hoverRegionHeight ?? 2) : 0)
                y: dockWindow.height - height
            }

            // Fixed at the revealed position; the body slides inside it.
            MouseArea {
                id: hoverArea
                x: dockWindow.bodyX - dockWindow.jointRadius
                y: dockWindow.height - dockWindow.dockHeight
                width: dockWindow.bodyWidth + dockWindow.jointRadius * 2
                height: dockWindow.dockHeight
                hoverEnabled: true
                acceptedButtons: Qt.NoButton
                focus: root.toggledOpen
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Escape)
                        root.toggledOpen = false;
                }

                readonly property real offset: dockWindow.dockHeight * (1 - dockWindow.shown)

                // Edge light, soft halo: below the body so it only leaks outward.
                DockEdgeLight {
                    soft: true
                    x: dockWindow.jointRadius - edgeOffset
                    y: hoverArea.offset - bleed
                    bodyWidth: dockWindow.bodyWidth
                    bodyHeight: dockWindow.dockHeight
                    jointRadius: dockWindow.jointRadius
                    cornerRadius: dockWindow.cornerRadius
                    opacity: dockWindow.shown
                }

                // Concave joints so the body reads as extruded from the edge.
                RoundCorner {
                    x: dockWindow.jointRadius - implicitSize
                    y: hoverArea.height - implicitSize
                    implicitSize: Math.min(dockWindow.jointRadius, dockWindow.dockHeight * dockWindow.shown)
                    corner: RoundCorner.CornerEnum.BottomRight
                    color: body.color
                }
                RoundCorner {
                    x: dockWindow.jointRadius + dockWindow.bodyWidth
                    y: hoverArea.height - implicitSize
                    implicitSize: Math.min(dockWindow.jointRadius, dockWindow.dockHeight * dockWindow.shown)
                    corner: RoundCorner.CornerEnum.BottomLeft
                    color: body.color
                }

                Rectangle { // Fixed-size body; the animation is a pure translation
                    id: body
                    x: dockWindow.jointRadius
                    y: hoverArea.offset
                    width: dockWindow.bodyWidth
                    height: dockWindow.dockHeight
                    // Same surface as the bar and the rails.
                    color: Appearance.colors.colLayer0
                    topLeftRadius: dockWindow.cornerRadius
                    topRightRadius: dockWindow.cornerRadius

                    Row {
                        id: contentRow
                        anchors.centerIn: parent
                        spacing: Math.round(dockWindow.padding * 0.5)
                        opacity: dockWindow.contentStage

                        DockButton {
                            anchors.verticalCenter: parent.verticalCenter
                            size: Math.round(dockWindow.buttonSize * 0.75)
                            buttonIcon: "keep"
                            tooltip: root.pinned ? Translation.tr("Stop keeping the dock open") : Translation.tr("Keep the dock open")
                            toggled: root.pinned
                            onClicked: root.pinned = !root.pinned
                        }
                        DockApps {
                            id: dockApps
                            anchors.verticalCenter: parent.verticalCenter
                            buttonSize: dockWindow.buttonSize
                            popupBaseY: dockWindow.height - dockWindow.dockHeight - 4
                        }
                        DockButton {
                            anchors.verticalCenter: parent.verticalCenter
                            size: Math.round(dockWindow.buttonSize * 0.75)
                            buttonIcon: "apps"
                            tooltip: Translation.tr("Launcher")
                            onClicked: GlobalStates.overviewOpen = !GlobalStates.overviewOpen
                        }
                    }
                }

                // Edge light, crisp rim: above the body, exactly on its outline.
                DockEdgeLight {
                    id: rimLight
                    x: dockWindow.jointRadius - edgeOffset
                    y: hoverArea.offset - bleed
                    bodyWidth: dockWindow.bodyWidth
                    bodyHeight: dockWindow.dockHeight
                    jointRadius: dockWindow.jointRadius
                    cornerRadius: dockWindow.cornerRadius
                    opacity: dockWindow.shown
                }
            }
        }
    }

    IpcHandler {
        target: "dock"

        function toggle(): void {
            root.toggledOpen = !root.toggledOpen;
        }

        function close(): void {
            root.toggledOpen = false;
        }

        function open(): void {
            root.toggledOpen = true;
        }
    }

    GlobalShortcut {
        name: "dockToggle"
        description: "Toggles the dock on press"

        onPressed: {
            root.toggledOpen = !root.toggledOpen;
        }
    }
}
