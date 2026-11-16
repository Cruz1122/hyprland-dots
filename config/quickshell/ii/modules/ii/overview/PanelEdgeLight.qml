pragma ComponentBehavior: Bound
import qs
import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import qs.services
import "../bar/IridescentPalette.js" as Palette

// Light running along one side of the launcher panel: fading in along the
// underside of the bar, into the root of the concave joint, around the joint
// and down the lateral edge, fading out before the bottom corner. Uses the bar pills' current color: iridescent
// while media is playing or the performance profile is on, gold otherwise.
//
// Drawn for the left side; `mirrored` flips it for the right side. Local
// geometry: the panel edge sits at x = edgeOffset, the bar at y = 0.
Item {
    id: root
    property bool mirrored: false
    // true: wide blurred halo; false: thin crisp rim line.
    property bool soft: false
    property real jointRadius: 23
    property real cornerRadius: 33
    property real fullHeight: 0
    property real visibleHeight: fullHeight
    // Room around the stroke for the blur to spread into.
    readonly property real bleed: 36
    // Length of the faded run along the underside of the bar.
    property real lead: 28
    // Distance from this item's left side to the panel edge it lights.
    readonly property real edgeOffset: bleed + lead + jointRadius
    readonly property bool iridescent: GlobalStates.iridescent
    readonly property color idleColor: "#F6D77A"
    property real phase: 0
    property real pulse: 1
    // Where the light dies out, as a fraction of the item height.
    readonly property real fadeEnd: Math.max(0.05, Math.min(0.98, (visibleHeight - cornerRadius) / Math.max(1, height)))

    // 0 = base (gold), 1 = iridescent; cross-fades when playback starts or stops.
    property real iridescence: iridescent ? 1 : 0
    Behavior on iridescence {
        NumberAnimation { duration: 900; easing.type: Easing.InOutQuad }
    }

    function lightColor(position, alpha) {
        if (iridescence <= 0)
            return Qt.rgba(idleColor.r, idleColor.g, idleColor.b, alpha);
        const cool = Qt.hsla(Palette.hue(phase, position), 1, 0.72, 1);
        return Qt.rgba(idleColor.r + (cool.r - idleColor.r) * iridescence,
            idleColor.g + (cool.g - idleColor.g) * iridescence,
            idleColor.b + (cool.b - idleColor.b) * iridescence, alpha);
    }

    width: edgeOffset + bleed
    height: fullHeight
    visible: opacity > 0 && fullHeight > 0
    transform: Scale {
        xScale: root.mirrored ? -1 : 1
        origin.x: root.width / 2
    }

    NumberAnimation on phase {
        // Keeps rotating until the fade back to the base color has finished.
        running: root.visible && root.iridescence > 0
        from: 0
        to: 1
        duration: 6000 // motion-ok: endless hue rotation, same pace as the bar pills
        loops: Animation.Infinite
    }
    SequentialAnimation on pulse {
        running: root.visible
        loops: Animation.Infinite
        NumberAnimation { to: 0.7; duration: 1600; easing.type: Easing.InOutSine } // motion-ok: endless breathing loop
        NumberAnimation { to: 1; duration: 1600; easing.type: Easing.InOutSine } // motion-ok: endless breathing loop
    }

    // (Inline components fail to resolve in this file under Quickshell
    // ("is not a type"), hence the repeated bindings below.)
    Loader { // Crisp rim
        anchors.fill: parent
        active: !root.soft
        sourceComponent: EdgeLightBand {
            thickness: 1.5
            bleed: root.bleed
            lead: root.lead
            jointRadius: root.jointRadius
            cornerRadius: root.cornerRadius
            fadeEnd: root.fadeEnd
            colorTop: root.lightColor(0, 1)
            colorMid: root.lightColor(0.5, 1)
            colorEnd: root.lightColor(1, 0)
            opacity: root.pulse
            // Explicit antialiasing for the thin arc: multisampled, 2x
            // supersampled layer.
            layer.enabled: true
            layer.smooth: true
            layer.samples: 4
            layer.textureSize: Qt.size(Math.ceil(width) * 2, Math.ceil(height) * 2)
        }
    }

    Loader { // Halo
        anchors.fill: parent
        active: root.soft
        sourceComponent: Item {
            opacity: root.pulse
            layer.enabled: true
            layer.smooth: true
            layer.effect: MultiEffect {
                blurEnabled: true
                blur: 1
                blurMax: 48
            }
            EdgeLightBand {
                anchors.fill: parent
                thickness: 8
                bleed: root.bleed
                lead: root.lead
                topInset: 0.75 // same path as the crisp rim
                jointRadius: root.jointRadius
                cornerRadius: root.cornerRadius
                fadeEnd: root.fadeEnd
                colorTop: root.lightColor(0, 1)
                colorMid: root.lightColor(0.5, 1)
                colorEnd: root.lightColor(1, 0)
            }
        }
    }
}
