import qs.modules.common
import qs.modules.ii.bar
import Qt5Compat.GraphicalEffects
import QtQuick

// Display text sized to its ink (no line-box padding, so it can sit flush
// against an edge) that can wear the bar pills' iridescent sweep.
Item {
    id: root
    property alias text: label.text
    property alias font: label.font
    property color color: Appearance.colors.colOnLayer0
    property bool iridescent: false
    // Size the item to the ink. Off, it keeps the text's own line box, which
    // for an icon font is the icon's design square.
    property bool tight: true
    readonly property rect ink: metrics.tightBoundingRect

    implicitWidth: tight ? Math.ceil(ink.width) : label.implicitWidth
    implicitHeight: tight ? Math.ceil(ink.height) : label.implicitHeight

    TextMetrics {
        id: metrics
        font: label.font
        text: label.text
    }

    Item {
        x: root.tight ? -root.ink.x : 0
        y: root.tight ? -(label.baselineOffset + root.ink.y) : 0
        width: label.implicitWidth
        height: label.implicitHeight

        Text {
            id: label
            color: root.color
            // Rasterized at its real size: distance-field text goes soft at
            // poster sizes, and curve rendering draws the seams of the
            // overlapping contours in variable fonts.
            renderType: Text.NativeRendering
        }

        IridescentFill { // Painted over the plain ink, cut to its glyphs
            radius: 0
            active: root.iridescent
            layer.enabled: visible
            layer.effect: OpacityMask {
                maskSource: label
            }
        }
    }
}
