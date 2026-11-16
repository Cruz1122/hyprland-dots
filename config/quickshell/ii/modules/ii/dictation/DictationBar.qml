pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.dock
import QtQuick
import Quickshell
import Quickshell.Wayland
import "../bar/IridescentPalette.js" as Palette

// Voice dictation bar, extruded from the bottom screen edge like the dock it
// replaces (same body, joints, edge light and reveal spring; see Dock.qml).
// Hidden until the pointer touches the edge or a dictation is running. It
// never takes keyboard focus: the text is typed into the focused window.
Scope {
    id: root

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: barWindow
            required property var modelData
            screen: modelData
            visible: !GlobalStates.screenLocked

            readonly property real barHeight: Config.options?.dictation.height ?? 60
            readonly property real padding: Math.round(barHeight * 0.1)
            readonly property real buttonSize: barHeight - padding * 2
            readonly property real jointRadius: Appearance.rounding.large
            readonly property real cornerRadius: Appearance.rounding.normal + padding
            // Follows the content, which changes with the dictation's phase.
            property real bodyWidth: contentRow.implicitWidth + padding * 4
            Behavior on bodyWidth {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
            readonly property real bodyX: Math.round((width - bodyWidth) / 2)
            readonly property bool hoverToReveal: Config.options?.dictation.hoverToReveal ?? true
            readonly property bool listening: Dictation.phase === "listening"
            readonly property bool transcribing: Dictation.phase === "transcribing"

            readonly property bool shouldShow: Dictation.phase !== "idle" || (hoverToReveal && hoverArea.containsMouse)

            // Same critically damped spring as Dock.stepReveal and
            // SideRail.stepReveal. Copied rather than shared; keep in sync.
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
                running: barWindow.reveal !== barWindow.revealTarget
                onTriggered: barWindow.stepReveal(frameTime)
            }
            readonly property real contentStage: Math.max(0, Math.min(1, (reveal - 0.25) / 0.45))

            anchors {
                bottom: true
                left: true
                right: true
            }
            exclusiveZone: 0
            // Room above the body for the edge light's halo.
            implicitHeight: barHeight + rimLight.bleed
            WlrLayershell.namespace: "quickshell:dictation"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            color: "transparent"

            mask: Region {
                item: inputRegion
            }
            // The visible part of the bar, or the reveal strip at the edge.
            Item {
                id: inputRegion
                x: barWindow.bodyX - barWindow.jointRadius
                width: barWindow.bodyWidth + barWindow.jointRadius * 2
                height: Math.max(barWindow.barHeight * barWindow.shown, barWindow.hoverToReveal ? 2 : 0)
                y: barWindow.height - height
            }

            // Fixed at the revealed position; the body slides inside it.
            MouseArea {
                id: hoverArea
                x: barWindow.bodyX - barWindow.jointRadius
                y: barWindow.height - barWindow.barHeight
                width: barWindow.bodyWidth + barWindow.jointRadius * 2
                height: barWindow.barHeight
                hoverEnabled: true
                acceptedButtons: Qt.NoButton

                readonly property real offset: barWindow.barHeight * (1 - barWindow.shown)

                DockEdgeLight { // Soft halo, below the body
                    soft: true
                    x: barWindow.jointRadius - edgeOffset
                    y: hoverArea.offset - bleed
                    bodyWidth: barWindow.bodyWidth
                    bodyHeight: barWindow.barHeight
                    jointRadius: barWindow.jointRadius
                    cornerRadius: barWindow.cornerRadius
                    opacity: barWindow.shown
                }

                RoundCorner {
                    x: barWindow.jointRadius - implicitSize
                    y: hoverArea.height - implicitSize
                    implicitSize: Math.min(barWindow.jointRadius, barWindow.barHeight * barWindow.shown)
                    corner: RoundCorner.CornerEnum.BottomRight
                    color: body.color
                }
                RoundCorner {
                    x: barWindow.jointRadius + barWindow.bodyWidth
                    y: hoverArea.height - implicitSize
                    implicitSize: Math.min(barWindow.jointRadius, barWindow.barHeight * barWindow.shown)
                    corner: RoundCorner.CornerEnum.BottomLeft
                    color: body.color
                }

                Rectangle { // Fixed-height body; the reveal is a pure translation
                    id: body
                    x: barWindow.jointRadius
                    y: hoverArea.offset
                    width: barWindow.bodyWidth
                    height: barWindow.barHeight
                    color: Appearance.colors.colLayer0
                    topLeftRadius: barWindow.cornerRadius
                    topRightRadius: barWindow.cornerRadius
                    clip: true // content of the next phase while the width catches up

                    Row {
                        id: contentRow
                        anchors.centerIn: parent
                        spacing: barWindow.padding * 2
                        opacity: barWindow.contentStage

                        DockButton {
                            anchors.verticalCenter: parent.verticalCenter
                            size: Math.round(barWindow.buttonSize * 0.86)
                            enabled: !barWindow.transcribing
                            buttonIcon: {
                                switch (Dictation.phase) {
                                case "listening":
                                    return "stop";
                                case "transcribing":
                                    return "more_horiz";
                                case "done":
                                    return "check";
                                case "error":
                                    return "mic_off";
                                default:
                                    return "mic";
                                }
                            }
                            onClicked: Dictation.toggle()
                        }

                        // The voice, mirrored around the middle: the newest
                        // sample at the center, older ones travelling outward.
                        // While transcribing the same bars carry a slow wave.
                        Item {
                            id: wave
                            anchors.verticalCenter: parent.verticalCenter
                            visible: barWindow.listening || barWindow.transcribing
                            opacity: Dictation.paused ? 0.35 : 1
                            Behavior on opacity {
                                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                            }
                            readonly property int barCount: 41
                            readonly property real barWidth: 3
                            readonly property real gap: 3
                            readonly property real half: (barCount - 1) / 2
                            implicitWidth: barCount * (barWidth + gap) - gap
                            implicitHeight: barWindow.buttonSize * 0.8

                            // Same rule and colors as the edge light: its base gold,
                            // iridescent only while the shell is (media playing or the
                            // performance profile).
                            readonly property color baseColor: rimLight.idleColor
                            property real iridescence: GlobalStates.iridescent ? 1 : 0
                            Behavior on iridescence {
                                animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                            }
                            function barColor(position) {
                                if (iridescence <= 0)
                                    return baseColor;
                                const cool = Qt.hsla(Palette.hue(huePhase, position), 1, 0.74, 1);
                                return Qt.rgba(baseColor.r + (cool.r - baseColor.r) * iridescence,
                                    baseColor.g + (cool.g - baseColor.g) * iridescence,
                                    baseColor.b + (cool.b - baseColor.b) * iridescence, 1);
                            }
                            property real huePhase: 0
                            NumberAnimation on huePhase {
                                running: wave.visible && wave.iridescence > 0
                                from: 0
                                to: 1
                                duration: 6000 // motion-ok: endless hue rotation, same pace as the edge light
                                loops: Animation.Infinite
                            }
                            // Samples arrive ~20 times a second; drawn as they come the
                            // shape would hop one bar at a time. `flow` is the fraction of
                            // a sample interval elapsed since the last one, stepped every
                            // frame, and the bars read the signal at that fractional age,
                            // so it glides outward continuously. A sample that arrives
                            // early leaves `flow` negative rather than jumping.
                            property real flow: 0
                            FrameAnimation {
                                running: barWindow.listening
                                onTriggered: wave.flow = Math.min(1, wave.flow + frameTime / Dictation.sampleInterval)
                            }
                            Connections {
                                target: Dictation
                                function onLevelsChanged() {
                                    wave.flow = Math.max(-0.5, wave.flow - 1);
                                }
                            }
                            function sampleAt(age) {
                                return Dictation.levels[Dictation.levels.length - 1 - age] ?? 0;
                            }
                            // Signal one interval in the past (the newest sample has
                            // nothing newer to blend toward) plus `age` intervals.
                            function signalAt(age) {
                                const position = Math.max(0, age + 1 - flow);
                                const older = Math.floor(position);
                                const blend = position - older;
                                return sampleAt(older) * (1 - blend) + sampleAt(older + 1) * blend;
                            }

                            property real travel: 0
                            NumberAnimation on travel {
                                running: barWindow.transcribing
                                from: 0
                                to: 1
                                duration: 1400 // motion-ok: endless wave while the model works
                                loops: Animation.Infinite
                            }

                            Repeater {
                                model: wave.barCount
                                Rectangle {
                                    id: waveBar
                                    required property int index
                                    readonly property real distance: Math.abs(index - wave.half) / wave.half // 0 center .. 1 ends
                                    readonly property real value: {
                                        if (barWindow.transcribing)
                                            return 0.22 + 0.2 * Math.sin((wave.travel - distance * 1.5) * 2 * Math.PI);
                                        // Tapered toward the ends, so the shape reads as one gesture.
                                        return wave.signalAt(distance * (Dictation.historyLength - 3)) * (1 - 0.55 * distance);
                                    }
                                    x: index * (wave.barWidth + wave.gap)
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: wave.barWidth
                                    radius: width / 2
                                    height: Math.max(width, wave.height * Math.min(1, value))
                                    color: wave.barColor(index / wave.barCount)
                                    opacity: 1 - 0.6 * distance
                                }
                            }
                        }

                        StyledText { // Timer, or what went wrong
                            anchors.verticalCenter: parent.verticalCenter
                            visible: barWindow.listening || Dictation.phase === "error"
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.features: ({ "tnum": 1 })
                            color: Dictation.phase === "error" ? Appearance.colors.colError : Appearance.colors.colSubtext
                            text: Dictation.phase === "error" ? Dictation.errorText : `${Math.floor(Dictation.elapsedSeconds / 60)}:${String(Dictation.elapsedSeconds % 60).padStart(2, "0")}`
                        }

                        DockButton {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: barWindow.listening
                            size: Math.round(barWindow.buttonSize * 0.7)
                            buttonIcon: Dictation.paused ? "play_arrow" : "pause"
                            onClicked: Dictation.togglePause()
                        }
                        DockButton {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: barWindow.listening
                            size: Math.round(barWindow.buttonSize * 0.7)
                            buttonIcon: "close"
                            onClicked: Dictation.cancel()
                        }
                    }
                }

                DockEdgeLight { // Crisp rim, on the body's outline
                    id: rimLight
                    x: barWindow.jointRadius - edgeOffset
                    y: hoverArea.offset - bleed
                    bodyWidth: barWindow.bodyWidth
                    bodyHeight: barWindow.barHeight
                    jointRadius: barWindow.jointRadius
                    cornerRadius: barWindow.cornerRadius
                    opacity: barWindow.shown
                }
            }
        }
    }
}
