pragma ComponentBehavior: Bound
import qs
import QtQuick
import QtQuick.Effects
import "../bar/IridescentPalette.js" as Palette

// The side rails' edge light (PanelEdgeLight) for the dock: same colors,
// breathing and iridescence, but traced around a body that rises from the
// bottom screen edge. PanelEdgeLight only draws a joint plus one straight
// side, which cannot follow the dock's top edge.
//
// Local geometry: the dock body's left edge is x = edgeOffset, its top is
// y = bleed, the screen edge is this item's bottom.
Item {
    id: root
    // true: wide blurred halo; false: thin crisp rim line.
    property bool soft: false
    property real bodyWidth: 0
    property real bodyHeight: 60
    property real jointRadius: 23
    property real cornerRadius: 23
    // Room around the stroke for the blur to spread into.
    readonly property real bleed: 36
    // Length of the faded run along the screen edge.
    property real lead: 28
    readonly property real edgeOffset: bleed + lead + jointRadius
    // Light left over the middle of the top edge; the two sides fade into it.
    property real centerAlpha: 0.18
    readonly property bool iridescent: GlobalStates.iridescent
    readonly property color idleColor: "#F6D77A"
    property real phase: 0
    property real pulse: 1

    // 0 = base (gold), 1 = iridescent; cross-fades when playback starts or stops.
    property real iridescence: iridescent ? 1 : 0
    Behavior on iridescence {
        NumberAnimation { duration: 900; easing.type: Easing.InOutQuad }
    }

    // Same mix as PanelEdgeLight.lightColor.
    function lightColor(position, alpha) {
        if (iridescence <= 0)
            return Qt.rgba(idleColor.r, idleColor.g, idleColor.b, alpha);
        const cool = Qt.hsla(Palette.hue(phase, position), 1, 0.72, 1);
        return Qt.rgba(idleColor.r + (cool.r - idleColor.r) * iridescence,
            idleColor.g + (cool.g - idleColor.g) * iridescence,
            idleColor.b + (cool.b - idleColor.b) * iridescence, alpha);
    }

    width: bodyWidth + edgeOffset * 2
    height: bodyHeight + bleed
    visible: opacity > 0 && bodyWidth > 0

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

    Loader { // Crisp rim
        anchors.fill: parent
        active: !root.soft
        sourceComponent: DockEdgeBand {
            thickness: 1.5
            bleed: root.bleed
            lead: root.lead
            jointRadius: root.jointRadius
            cornerRadius: root.cornerRadius
            bodyHeight: root.bodyHeight
            colorEdge: root.lightColor(0, 0)
            colorSide: root.lightColor(0.15, 1)
            colorCenter: root.lightColor(0.5, root.centerAlpha)
            colorSideRight: root.lightColor(0.85, 1)
            colorEdgeRight: root.lightColor(1, 0)
            opacity: root.pulse
            // Explicit antialiasing for the thin arcs: multisampled, 2x
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
            DockEdgeBand {
                anchors.fill: parent
                thickness: 8
                bleed: root.bleed
                lead: root.lead
                bottomInset: 0.75 // same path as the crisp rim
                jointRadius: root.jointRadius
                cornerRadius: root.cornerRadius
                bodyHeight: root.bodyHeight
                colorEdge: root.lightColor(0, 0)
                colorSide: root.lightColor(0.15, 1)
                colorCenter: root.lightColor(0.5, root.centerAlpha)
                colorSideRight: root.lightColor(0.85, 1)
                colorEdgeRight: root.lightColor(1, 0)
            }
        }
    }
}
