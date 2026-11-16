import qs.modules.common
import QtQuick

// Date, a very large symbol, then the topic and its one-line hook, on the
// center axis.
Item {
    id: root
    required property var poster
    // The composition is drawn a touch smaller than the safe area allows, so
    // it reads as a poster rather than filling the screen. The only size knob.
    // The holding message is read from across a room, so it is drawn larger
    // and its labels heavier.
    readonly property real sizeScale: poster.presenting ? 0.9 : 0.62
    readonly property int labelWeight: poster.presenting ? Font.Bold : Font.DemiBold
    readonly property real u: poster.unit * sizeScale

    // The labels stay put on every workspace: the date's baseline and the
    // term's cap line sit this far from the center. The symbol is centered
    // between them, so whatever its shape, both gaps are equal.
    readonly property real labelDistance: 315 * u

    function centerX(item) { return (width - item.width) / 2; }
    // Letter spacing is also added after the last glyph of each line, which
    // would push the ink left of the axis; the spaced labels shift it back.
    function labelX(item) { return centerX(item) + item.font.letterSpacing / 2; }

    PosterSymbol {
        id: symbol
        x: root.centerX(this)
        // Shifted so the ink, not the design square, is centered.
        y: (root.height - height) / 2 + root.poster.symbolLift * size
        size: 440 * root.u
        text: root.poster.symbol
        iridescent: root.poster.iridescent
    }
    Text {
        id: date
        x: root.labelX(this)
        y: root.height / 2 - root.labelDistance - baselineOffset
        text: root.poster.dateText.toUpperCase()
        color: Appearance.colors.colOnLayer0
        renderType: Text.CurveRendering
        font {
            family: Appearance.font.family.title
            pixelSize: 34 * root.u
            weight: root.labelWeight
            letterSpacing: 12 * root.u
        }
    }
    TextMetrics { // Height of a capital letter in the term's font
        id: termCapital
        font: term.font
        text: "H"
    }
    PosterQuote { // Set exactly like the date, so the two labels pair up
        id: term
        x: root.labelX(this)
        y: root.height / 2 + root.labelDistance - (baselineOffset - termCapital.tightBoundingRect.height)
        side: 0
        maximumWidth: 1300 * root.u
        text: root.poster.term.toUpperCase()
        color: Appearance.colors.colOnLayer0

        MouseArea { // Looks the topic up on the web, in the default browser
            anchors.fill: parent
            enabled: !root.poster.presenting
            cursorShape: Qt.PointingHandCursor
            onClicked: Qt.openUrlExternally(Config.options.search.engineBaseUrl + encodeURIComponent(root.poster.term))
        }
        font {
            family: date.font.family
            pixelSize: date.font.pixelSize
            weight: date.font.weight
            letterSpacing: date.font.letterSpacing
        }
    }
    PosterQuote {
        x: root.centerX(this)
        y: term.y + term.height + 22 * root.u
        side: 0
        maximumWidth: 1100 * root.u
        text: root.poster.text
        font.pixelSize: 26 * root.u
        font.weight: root.poster.presenting ? Font.Medium : Font.Normal
    }
}
