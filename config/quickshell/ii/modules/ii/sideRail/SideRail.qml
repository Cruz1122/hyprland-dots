pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.overview
import QtQuick

// Full-height rail that slides out of a screen edge, flush under the bar and
// joined to it by a concave corner, with the launcher panel's edge light on
// its inner edge. Fill the hosting PanelWindow with it; the window must be at
// least `windowWidth` wide and anchored to the rail's screen edge.
Item {
    id: root
    property bool rightSide: false
    property bool open: false
    // Extension waits for the surface to be mapped so the first frames are not
    // lost to window setup.
    property bool surfaceReady: true
    property real railWidth: 440
    readonly property real panelRadius: Appearance.rounding.large + 10
    readonly property real jointRadius: Appearance.rounding.large
    // Room past the inner edge for the joint and the edge light.
    readonly property real overhang: jointRadius + 28 + 36 // PanelEdgeLight lead + bleed
    readonly property real windowWidth: railWidth + overhang
    // Keep the window mapped until the retract animation finishes.
    readonly property bool mapped: open || reveal > 0
    // Visible part of the rail, for the window's input mask.
    readonly property Item hitbox: hitboxItem
    default property alias content: contentHolder.data

    readonly property real revealTarget: (open && surfaceReady) ? 1 : 0
    property real reveal: 0
    property real revealVelocity: 0
    readonly property real shown: Math.max(0, Math.min(1, reveal))
    // Window x of the rail's inner edge.
    readonly property real edgeX: rightSide ? width - railWidth * shown : railWidth * shown

    // Staggered entrance: block `index` starts a little after the previous
    // one. Pure functions of `reveal`, so they follow the spring both ways.
    function stage(index) {
        return Math.max(0, Math.min(1, (reveal - 0.25 - index * 0.08) / 0.45));
    }
    function stageOffset(index) {
        return (rightSide ? 18 : -18) * (1 - stage(index));
    }

    // Same critically damped spring as the launcher panel (see Overview.qml):
    // stepped once per rendered frame, keeps its velocity when the target
    // flips mid-flight.
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
        running: root.reveal !== root.revealTarget
        onTriggered: root.stepReveal(frameTime)
    }

    Item {
        id: hitboxItem
        x: root.rightSide ? root.edgeX : 0
        width: root.railWidth * root.shown
        height: parent.height
    }

    // Edge light, soft halo: below the rail so it only leaks outward.
    PanelEdgeLight {
        soft: true
        mirrored: !root.rightSide
        x: root.rightSide ? root.edgeX - edgeOffset : root.edgeX - bleed
        jointRadius: root.jointRadius
        cornerRadius: root.panelRadius
        fullHeight: root.height
        opacity: root.shown
    }

    // Concave joint so the rail reads as extruded from the bar.
    RoundCorner {
        x: root.rightSide ? root.edgeX - implicitSize : root.edgeX
        implicitSize: Math.min(root.jointRadius, root.railWidth * root.shown)
        corner: root.rightSide ? RoundCorner.CornerEnum.TopRight : RoundCorner.CornerEnum.TopLeft
        color: railBackground.color
    }

    Item { // Fixed-size rail; the animation is a pure translation
        x: root.rightSide ? root.edgeX : root.edgeX - root.railWidth
        width: root.railWidth
        height: parent.height

        Rectangle {
            id: railBackground
            anchors.fill: parent
            // Same surface as the bar, so both read as one piece.
            color: Appearance.colors.colLayer0
            bottomRightRadius: root.rightSide ? 0 : root.panelRadius
            bottomLeftRadius: root.rightSide ? root.panelRadius : 0
        }

        Item {
            id: contentHolder
            anchors.fill: parent
        }
    }

    // Edge light, crisp rim: above the rail, exactly on its outline.
    PanelEdgeLight {
        mirrored: !root.rightSide
        x: root.rightSide ? root.edgeX - edgeOffset : root.edgeX - bleed
        jointRadius: root.jointRadius
        cornerRadius: root.panelRadius
        fullHeight: root.height
        opacity: root.shown
    }
}
