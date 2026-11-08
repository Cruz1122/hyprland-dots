import QtQuick
import QtQuick.Shapes
import qs.modules.common
import qs.modules.common.widgets
import "CurveMath.js" as CurveMath

// Small drawing of a curve's timing (time left to right, progress bottom to
// top). The y range is fitted to the curve inside Hyprland's [-1, 2], with
// faint guides at the start (0) and end (1) positions. `curve` is a curve
// descriptor; without one (an unrecognized curve) it shows a question mark.
Rectangle {
    id: root

    property var curve: null
    property bool selected: false
    // Hover is tracked here; `forceHovered` lets a parent (or the harness)
    // show the hover state.
    property bool forceHovered: false
    property bool focusShown: false
    property int samples: 64
    readonly property bool hovered: hover.hovered || root.forceHovered
    readonly property var points: root.curve ? CurveMath.sample(root.curve, root.samples) : []
    readonly property real yLow: Math.max(CurveMath.Y_MIN, Math.min(0, ...root.points.map(p => p.y)))
    readonly property real yHigh: Math.min(CurveMath.Y_MAX, Math.max(1, ...root.points.map(p => p.y)))
    readonly property real inset: 8
    readonly property real plotWidth: Math.max(1, root.width - 2 * root.inset)
    readonly property real plotHeight: Math.max(1, root.height - 2 * root.inset)
    readonly property color strokeColor: !root.enabled ? Appearance.colors.colOnLayer2Disabled
        : root.selected ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer2
    readonly property color guideColor: Appearance.colors.colOutlineVariant

    function mapX(x) {
        return root.inset + x * root.plotWidth;
    }

    function mapY(y) {
        const span = Math.max(1e-6, root.yHigh - root.yLow);
        const clamped = Math.max(root.yLow, Math.min(root.yHigh, y));
        return root.inset + (root.yHigh - clamped) / span * root.plotHeight;
    }

    implicitWidth: 88
    implicitHeight: 56
    radius: SettingsMetrics.controlRadius
    color: root.selected ? Appearance.colors.colSecondaryContainer
        : root.hovered && root.enabled ? Appearance.colors.colLayer2Hover : Appearance.colors.colLayer2
    border.width: root.selected ? 2 : 1
    border.color: root.selected ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant
    opacity: root.enabled ? 1 : 0.6

    Behavior on color {
        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
    }

    HoverHandler {
        id: hover
    }

    // Guides: crisp 1 px rectangles snapped to whole pixels.
    Repeater {
        model: root.curve ? [0, 1] : []

        delegate: Rectangle {
            required property real modelData
            x: root.inset
            y: Math.round(root.mapY(modelData))
            implicitWidth: root.plotWidth
            implicitHeight: 1
            color: root.guideColor
            opacity: 0.8
        }
    }

    Shape {
        id: plot
        anchors.fill: parent
        visible: root.curve !== null
        preferredRendererType: Shape.CurveRenderer
        antialiasing: true

        ShapePath {
            strokeColor: root.strokeColor
            strokeWidth: root.selected ? 2.5 : 2
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin

            PathPolyline {
                path: root.points.map(p => Qt.point(root.mapX(p.x), root.mapY(p.y)))
            }
        }
    }

    MaterialSymbol {
        anchors.centerIn: parent
        visible: root.curve === null
        text: "question_mark"
        iconSize: 22
        color: root.strokeColor
    }

    SettingsFocusRing {
        shown: root.focusShown
        ringRadius: root.radius
    }
}
