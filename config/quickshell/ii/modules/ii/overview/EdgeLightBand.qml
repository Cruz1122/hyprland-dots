import QtQuick
import QtQuick.Shapes

// One side of the launcher panel's edge light, drawn for the left side: a thin
// band that runs along the underside of the bar (fading in over `lead`), into
// the root of the concave joint, around the joint and down the panel edge
// (x = rootX + jointRadius). The bar's bottom edge is y = 0.
//
// It is a filled band rather than a stroke so it can carry a gradient and
// still be antialiased by the renderer; masking a gradient with a stencil
// texture produced jagged edges.
Shape {
    id: band
    required property real thickness
    property real bleed: 0
    // Length of the faded run along the bar before the joint.
    property real lead: 0
    // Pushes the top of the path down so the run under the bar is not clipped
    // by the window's top edge.
    property real topInset: thickness / 2
    property real jointRadius: 23
    property real cornerRadius: 33
    // Where the light dies out, as a fraction of the height.
    property real fadeEnd: 0.9
    property color colorTop: "white"
    property color colorMid: "white"
    property color colorEnd: "transparent"

    readonly property real rootX: bleed + lead
    readonly property real centerY: jointRadius + topInset
    readonly property real edgeX: rootX + jointRadius
    readonly property real outerRadius: jointRadius + thickness / 2
    readonly property real innerRadius: Math.max(0.1, jointRadius - thickness / 2)
    readonly property real endY: Math.max(centerY, height - cornerRadius)

    preferredRendererType: Shape.CurveRenderer

    ShapePath {
        strokeWidth: 0
        strokeColor: "transparent"
        pathHints: ShapePath.PathNonIntersecting
        fillGradient: LinearGradient {
            x1: 0; y1: 0
            x2: 0; y2: band.height
            // Alpha carries the fade-out toward the bottom corner.
            GradientStop { position: 0; color: band.colorTop }
            GradientStop { position: band.fadeEnd * 0.55; color: band.colorMid }
            GradientStop { position: band.fadeEnd; color: band.colorEnd }
            GradientStop { position: 1; color: band.colorEnd }
        }
        startX: band.rootX
        startY: band.centerY - band.outerRadius
        PathAngleArc { // Outer side of the joint, bar -> panel edge
            moveToStart: false
            centerX: band.rootX
            centerY: band.centerY
            radiusX: band.outerRadius
            radiusY: band.outerRadius
            startAngle: -90
            sweepAngle: 90
        }
        PathLine { x: band.edgeX + band.thickness / 2; y: band.endY }
        PathLine { x: band.edgeX - band.thickness / 2; y: band.endY }
        PathLine { x: band.edgeX - band.thickness / 2; y: band.centerY }
        PathAngleArc { // Inner side of the joint, back up to the bar
            moveToStart: false
            centerX: band.rootX
            centerY: band.centerY
            radiusX: band.innerRadius
            radiusY: band.innerRadius
            startAngle: 0
            sweepAngle: -90
        }
        PathLine { x: band.rootX; y: band.centerY - band.outerRadius }
    }

    ShapePath { // Faded run along the underside of the bar
        strokeWidth: 0
        strokeColor: "transparent"
        pathHints: ShapePath.PathNonIntersecting
        fillGradient: LinearGradient {
            x1: band.bleed; y1: 0
            x2: band.rootX; y2: 0
            GradientStop { position: 0; color: Qt.rgba(band.colorTop.r, band.colorTop.g, band.colorTop.b, 0) }
            GradientStop { position: 1; color: band.colorTop }
        }
        startX: band.bleed
        startY: band.centerY - band.outerRadius
        PathLine { x: band.rootX; y: band.centerY - band.outerRadius }
        PathLine { x: band.rootX; y: band.centerY - band.innerRadius }
        PathLine { x: band.bleed; y: band.centerY - band.innerRadius }
        PathLine { x: band.bleed; y: band.centerY - band.outerRadius }
    }
}
