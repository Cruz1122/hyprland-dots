import QtQuick
import QtQuick.Shapes

// The dock's edge light as one filled band (see EdgeLightBand for why a band
// and not a stroke): a faded run along the screen's bottom edge, up the left
// concave joint and side, over the top edge, and back down the right side.
// The dock body spans x in [bodyLeft, bodyRight] and its top is bodyTop; the
// screen edge is this item's bottom.
Shape {
    id: band
    required property real thickness
    property real bleed: 0
    // Length of the faded run along the screen edge before each joint.
    property real lead: 0
    // Lifts the run along the screen edge so the window edge does not clip it.
    property real bottomInset: thickness / 2
    property real jointRadius: 23
    property real cornerRadius: 23
    property real bodyHeight: 60
    // 0..1 fractions of the band's width -> colors; alpha carries the fades.
    property color colorEdge: "transparent"
    property color colorSide: "white"
    property color colorCenter: "white"
    property color colorSideRight: colorSide
    property color colorEdgeRight: colorEdge

    readonly property real half: thickness / 2
    readonly property real bodyLeft: bleed + lead + jointRadius
    readonly property real bodyRight: width - bodyLeft
    readonly property real bottomY: height - bottomInset
    readonly property real bodyTop: height - bodyHeight
    // Keeps the straight sides non-negative on very short docks.
    readonly property real topRadius: Math.max(0, Math.min(cornerRadius, bodyHeight - jointRadius - bottomInset))
    readonly property real jointCenterY: bottomY - jointRadius
    readonly property real leftJointX: bodyLeft - jointRadius
    readonly property real rightJointX: bodyRight + jointRadius
    readonly property real span: Math.max(1, width - bleed * 2)
    readonly property real jointStop: lead / span
    readonly property real cornerStop: Math.min(0.45, (lead + jointRadius + topRadius) / span)

    preferredRendererType: Shape.CurveRenderer

    ShapePath {
        strokeWidth: 0
        strokeColor: "transparent"
        pathHints: ShapePath.PathNonIntersecting
        fillGradient: LinearGradient {
            x1: band.bleed; y1: 0
            x2: band.width - band.bleed; y2: 0
            GradientStop { position: 0; color: band.colorEdge }
            GradientStop { position: band.jointStop; color: band.colorSide }
            GradientStop { position: band.cornerStop; color: band.colorSide }
            GradientStop { position: 0.5; color: band.colorCenter }
            GradientStop { position: 1 - band.cornerStop; color: band.colorSideRight }
            GradientStop { position: 1 - band.jointStop; color: band.colorSideRight }
            GradientStop { position: 1; color: band.colorEdgeRight }
        }

        // Air side of the outline, left to right.
        startX: band.bleed
        startY: band.bottomY - band.half
        PathLine { x: band.leftJointX; y: band.bottomY - band.half }
        PathAngleArc {
            moveToStart: false
            centerX: band.leftJointX; centerY: band.jointCenterY
            radiusX: band.jointRadius - band.half; radiusY: radiusX
            startAngle: 90; sweepAngle: -90
        }
        PathLine { x: band.bodyLeft - band.half; y: band.bodyTop + band.topRadius }
        PathAngleArc {
            moveToStart: false
            centerX: band.bodyLeft + band.topRadius; centerY: band.bodyTop + band.topRadius
            radiusX: band.topRadius + band.half; radiusY: radiusX
            startAngle: 180; sweepAngle: 90
        }
        PathLine { x: band.bodyRight - band.topRadius; y: band.bodyTop - band.half }
        PathAngleArc {
            moveToStart: false
            centerX: band.bodyRight - band.topRadius; centerY: band.bodyTop + band.topRadius
            radiusX: band.topRadius + band.half; radiusY: radiusX
            startAngle: 270; sweepAngle: 90
        }
        PathLine { x: band.bodyRight + band.half; y: band.jointCenterY }
        PathAngleArc {
            moveToStart: false
            centerX: band.rightJointX; centerY: band.jointCenterY
            radiusX: band.jointRadius - band.half; radiusY: radiusX
            startAngle: 180; sweepAngle: -90
        }
        PathLine { x: band.width - band.bleed; y: band.bottomY - band.half }

        // Body side of the outline, back right to left.
        PathLine { x: band.width - band.bleed; y: band.bottomY + band.half }
        PathLine { x: band.rightJointX; y: band.bottomY + band.half }
        PathAngleArc {
            moveToStart: false
            centerX: band.rightJointX; centerY: band.jointCenterY
            radiusX: band.jointRadius + band.half; radiusY: radiusX
            startAngle: 90; sweepAngle: 90
        }
        PathLine { x: band.bodyRight - band.half; y: band.bodyTop + band.topRadius }
        PathAngleArc {
            moveToStart: false
            centerX: band.bodyRight - band.topRadius; centerY: band.bodyTop + band.topRadius
            radiusX: Math.max(0.1, band.topRadius - band.half); radiusY: radiusX
            startAngle: 0; sweepAngle: -90
        }
        PathLine { x: band.bodyLeft + band.topRadius; y: band.bodyTop + band.half }
        PathAngleArc {
            moveToStart: false
            centerX: band.bodyLeft + band.topRadius; centerY: band.bodyTop + band.topRadius
            radiusX: Math.max(0.1, band.topRadius - band.half); radiusY: radiusX
            startAngle: 270; sweepAngle: -90
        }
        PathLine { x: band.bodyLeft + band.half; y: band.jointCenterY }
        PathAngleArc {
            moveToStart: false
            centerX: band.leftJointX; centerY: band.jointCenterY
            radiusX: band.jointRadius + band.half; radiusY: radiusX
            startAngle: 0; sweepAngle: 90
        }
        PathLine { x: band.bleed; y: band.bottomY + band.half }
        PathLine { x: band.bleed; y: band.bottomY - band.half }
    }
}
