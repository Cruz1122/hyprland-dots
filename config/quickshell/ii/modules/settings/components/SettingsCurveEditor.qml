import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Shapes
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
import "CurveMath.js" as CurveMath

// Editor for a bezier curve's two control points [x1, y1, x2, y2]. `points`
// is the curve to show and may be bound by the parent: the editor never
// assigns it. It edits its own copy (`editedPoints`, read-only for the
// parent) and loads `points` again whenever they change from outside (undo,
// reset, a backend revert). Every change emits changed(points); the end of
// each edit (drag release, Enter or focus loss in a field, an arrow-key step,
// "Start from…") also emits accepted(points). x is kept in [0, 1] and y in [-1, 2] (Hyprland
// accepts x outside [0, 1], but the timing then stops being monotonic), and
// values are rounded to 2 decimals.
//
// `originalPoints` (optional) is drawn in grey for comparison. `baseCurves` are bezier descriptors with `label` offered by
// "Start from…". The ball under the plot previews the motion on demand,
// lasting `durationMs`.
Item {
    id: root

    property var points: CurveMath.LINEAR_POINTS
    // The points shown and edited. Read-only for the parent: assign `points`
    // instead.
    property var editedPoints: root.normalized(root.points)
    property var originalPoints: null
    property var baseCurves: []
    property real durationMs: 500
    readonly property bool compact: root.width < 560
    property real ballProgress: 1
    readonly property bool previewing: ballAnimation.running

    // Hint of each invalid field (index = coordinate); the first one shows
    // under the fields.
    property var fieldErrors: ["", "", "", ""]
    readonly property string invalidMessage: root.fieldErrors.find(e => e.length > 0) ?? ""

    signal changed(var points)
    signal accepted(var points)

    function round2(v) {
        return Math.round(v * 100) / 100;
    }

    function normalized(points) {
        return CurveMath.clampPoint(points).map(v => root.round2(v));
    }

    // Applies an edit; returns false when nothing changed.
    function setPoints(points, finished) {
        const next = root.normalized(points);
        const same = next.every((v, i) => v === root.editedPoints[i]);
        if (!same) {
            root.editedPoints = next;
            root.changed(next);
        }
        if (finished)
            root.accepted(root.editedPoints);
        return !same;
    }

    function setFieldError(index, message) {
        const next = root.fieldErrors.slice();
        next[index] = message;
        root.fieldErrors = next;
    }

    function setCoordinate(index, value, finished) {
        const next = root.editedPoints.slice();
        next[index] = value;
        return root.setPoints(next, finished);
    }

    function step(index, delta, finished) {
        return root.setCoordinate(index, root.round2(root.editedPoints[index] + delta), finished);
    }

    function preview() {
        ballAnimation.stop();
        root.ballProgress = 0;
        ballAnimation.start();
    }

    // The binding on editedPoints breaks at the first edit; this keeps
    // loading the parent's points after that.
    onPointsChanged: root.editedPoints = root.normalized(root.points)

    implicitWidth: layout.implicitWidth
    implicitHeight: layout.implicitHeight

    GridLayout {
        id: layout
        anchors.left: parent.left
        anchors.right: parent.right
        columns: root.compact ? 1 : 2
        columnSpacing: 20
        rowSpacing: 14

        ColumnLayout {
            Layout.alignment: Qt.AlignTop
            Layout.fillWidth: root.compact
            Layout.maximumWidth: root.compact ? Number.POSITIVE_INFINITY : 300
            spacing: 10

            Rectangle {
                id: plotFrame
                // y spans Hyprland's whole [-1, 2]; the drawing keeps a
                // margin so the handles stay grabbable at the edges.
                readonly property real margin: 14
                readonly property real plotWidth: Math.max(1, plotFrame.width - 2 * plotFrame.margin)
                readonly property real plotHeight: Math.max(1, plotFrame.height - 2 * plotFrame.margin)

                function mapX(x) {
                    return plotFrame.margin + x * plotFrame.plotWidth;
                }
                function mapY(y) {
                    return plotFrame.margin + (CurveMath.Y_MAX - y) / (CurveMath.Y_MAX - CurveMath.Y_MIN) * plotFrame.plotHeight;
                }
                function unmapX(px) {
                    return (px - plotFrame.margin) / plotFrame.plotWidth;
                }
                function unmapY(py) {
                    return CurveMath.Y_MAX - (py - plotFrame.margin) / plotFrame.plotHeight * (CurveMath.Y_MAX - CurveMath.Y_MIN);
                }
                function polyline(points) {
                    return CurveMath.sample({ type: "bezier", points: points }, 96).map(p => Qt.point(plotFrame.mapX(p.x), plotFrame.mapY(p.y)));
                }

                Layout.fillWidth: root.compact
                Layout.preferredWidth: root.compact ? -1 : 300
                implicitWidth: 300
                implicitHeight: 270
                radius: SettingsMetrics.controlRadius
                color: Appearance.colors.colLayer2
                border.width: 1
                border.color: Appearance.colors.colOutlineVariant
                Accessible.role: Accessible.Graphic
                Accessible.name: Translation.tr("Curve")

                // Time 0 and 1 (vertical) and progress 0 and 1 (horizontal).
                Repeater {
                    model: [0, 1]

                    delegate: Rectangle {
                        required property real modelData
                        x: Math.round(plotFrame.mapX(modelData))
                        y: plotFrame.margin
                        implicitWidth: 1
                        implicitHeight: plotFrame.plotHeight
                        color: Appearance.colors.colOutlineVariant
                    }
                }

                Repeater {
                    model: [0, 1]

                    delegate: Item {
                        required property real modelData
                        y: Math.round(plotFrame.mapY(modelData))
                        implicitWidth: plotFrame.width
                        implicitHeight: 1

                        Rectangle {
                            x: plotFrame.margin
                            implicitWidth: plotFrame.plotWidth
                            implicitHeight: 1
                            color: Appearance.colors.colOutline
                            opacity: 0.6
                        }

                        StyledText {
                            // Start: under its line at the left; end: above
                            // its line at the right, away from typical curves.
                            x: modelData === 0 ? plotFrame.margin + 4 : plotFrame.margin + plotFrame.plotWidth - implicitWidth - 4
                            y: modelData === 0 ? 2 : -implicitHeight - 1
                            text: modelData === 0 ? Translation.tr("Start position") : Translation.tr("End position")
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.colors.colSubtext
                        }
                    }
                }

                Shape {
                    anchors.fill: parent
                    preferredRendererType: Shape.CurveRenderer
                    antialiasing: true

                    // The original curve, for comparison.
                    ShapePath {
                        strokeColor: Appearance.colors.colOutline
                        strokeWidth: 2
                        fillColor: "transparent"
                        capStyle: ShapePath.RoundCap
                        joinStyle: ShapePath.RoundJoin
                        PathPolyline {
                            path: root.originalPoints ? plotFrame.polyline(root.originalPoints) : []
                        }
                    }

                    // Handle arms: start -> first point, end -> second point.
                    ShapePath {
                        strokeColor: Appearance.colors.colOnLayer2
                        strokeWidth: 1
                        fillColor: "transparent"
                        startX: plotFrame.mapX(0)
                        startY: plotFrame.mapY(0)
                        PathLine { x: plotFrame.mapX(root.editedPoints[0]); y: plotFrame.mapY(root.editedPoints[1]) }
                        PathMove { x: plotFrame.mapX(1); y: plotFrame.mapY(1) }
                        PathLine { x: plotFrame.mapX(root.editedPoints[2]); y: plotFrame.mapY(root.editedPoints[3]) }
                    }

                    ShapePath {
                        strokeColor: Appearance.colors.colPrimary
                        strokeWidth: 2.5
                        fillColor: "transparent"
                        capStyle: ShapePath.RoundCap
                        joinStyle: ShapePath.RoundJoin
                        PathPolyline {
                            path: plotFrame.polyline(root.editedPoints)
                        }
                    }
                }

                Repeater {
                    model: 2

                    delegate: Item {
                        id: handle
                        required property int index
                        readonly property int xIndex: handle.index * 2
                        readonly property real size: 28

                        objectName: "curveHandle:" + handle.index
                        x: plotFrame.mapX(root.editedPoints[handle.xIndex]) - handle.size / 2
                        y: plotFrame.mapY(root.editedPoints[handle.xIndex + 1]) - handle.size / 2
                        implicitWidth: handle.size
                        implicitHeight: handle.size
                        z: 2

                        Rectangle {
                            anchors.centerIn: parent
                            implicitWidth: dragArea.pressed || dragArea.containsMouse ? 18 : 14
                            implicitHeight: implicitWidth
                            radius: implicitWidth / 2
                            color: Appearance.colors.colPrimary
                            border.width: 2
                            border.color: Appearance.colors.colLayer2
                            opacity: root.enabled ? 1 : 0.5
                        }

                        MouseArea {
                            id: dragArea
                            anchors.fill: parent
                            enabled: root.enabled
                            hoverEnabled: true
                            preventStealing: true
                            cursorShape: Qt.SizeAllCursor
                            onPositionChanged: mouse => {
                                if (!dragArea.pressed)
                                    return;
                                const p = dragArea.mapToItem(plotFrame, mouse.x, mouse.y);
                                const next = root.editedPoints.slice();
                                next[handle.xIndex] = plotFrame.unmapX(p.x);
                                next[handle.xIndex + 1] = plotFrame.unmapY(p.y);
                                root.setPoints(next, false);
                            }
                            onReleased: root.accepted(root.editedPoints)
                        }
                    }
                }
            }

            // Ball preview: travels from the start to the end position along
            // the curve; overshooting curves carry it past the end mark, but
            // never out of the track (y can reach -1 or 2: the ball stops at
            // the track's edge).
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Rectangle {
                    id: track
                    objectName: "curveTrack"
                    readonly property real ballSize: 16
                    readonly property real startX: track.width * 0.12
                    readonly property real endX: track.width * 0.78
                    readonly property real value: CurveMath.bezierY(root.editedPoints, root.ballProgress)

                    Layout.fillWidth: true
                    implicitHeight: 28
                    radius: height / 2
                    color: Appearance.colors.colLayer2
                    border.width: 1
                    border.color: Appearance.colors.colOutlineVariant
                    clip: true

                    Rectangle {
                        x: Math.round(track.endX)
                        anchors.verticalCenter: parent.verticalCenter
                        implicitWidth: 1
                        implicitHeight: track.height - 10
                        color: Appearance.colors.colOutline
                    }

                    Rectangle {
                        objectName: "curveBall"
                        readonly property real inset: (track.height - track.ballSize) / 2
                        x: Math.max(inset, Math.min(track.width - track.ballSize - inset,
                            track.startX + track.value * (track.endX - track.startX) - track.ballSize / 2))
                        anchors.verticalCenter: parent.verticalCenter
                        implicitWidth: track.ballSize
                        implicitHeight: track.ballSize
                        radius: track.ballSize / 2
                        color: Appearance.colors.colPrimary
                    }
                }

                SettingsIconButton {
                    iconName: "play_arrow"
                    tooltip: Translation.tr("Preview the motion")
                    enabled: root.enabled
                    onClicked: root.preview()
                }
            }
        }

        ColumnLayout {
            Layout.alignment: Qt.AlignTop
            Layout.fillWidth: true
            spacing: 12

            StyledComboBox {
                id: startFrom
                objectName: "curveStartFrom"
                Layout.fillWidth: true
                Layout.maximumWidth: SettingsMetrics.selectWidth
                visible: root.baseCurves.length > 0
                enabled: root.enabled
                model: root.baseCurves.map(c => ({ label: c.group === "user" ? String(c.label) : Translation.tr(String(c.label ?? c.name)) }))
                textRole: "label"
                displayText: Translation.tr("Start from…")
                currentIndex: -1
                Accessible.name: Translation.tr("Start from…")
                onActivated: index => {
                    const base = root.baseCurves[index];
                    if (base?.points)
                        root.setPoints(base.points, true);
                    startFrom.currentIndex = -1;
                }

                // StyledComboBox's delegate renders its label as AutoText, so
                // a user curve label with markup would be shown as rich text.
                // Same look (nothing is ever the current item here), plain text.
                delegate: ItemDelegate {
                    id: startFromItem
                    required property var model
                    required property int index
                    width: ListView.view ? ListView.view.width : startFrom.width // size-ok: a list delegate fills the popup width
                    implicitHeight: 40
                    hoverEnabled: true

                    background: Rectangle {
                        radius: Appearance.rounding.small
                        color: startFromItem.down ? Appearance.colors.colLayer3Active
                            : startFromItem.hovered || startFrom.highlightedIndex === startFromItem.index ? Appearance.colors.colLayer3Hover
                            : ColorUtils.transparentize(Appearance.colors.colLayer3)
                    }

                    contentItem: StyledText {
                        objectName: "curveStartFromLabel:" + startFromItem.index
                        leftPadding: 4
                        textFormat: Text.PlainText
                        text: startFromItem.model[startFrom.textRole]
                        elide: Text.ElideRight
                        verticalAlignment: Text.AlignVCenter
                        color: Appearance.colors.colOnLayer3
                    }
                }
            }

            Repeater {
                model: [
                    { title: Translation.tr("First point"), xIndex: 0 },
                    { title: Translation.tr("Second point"), xIndex: 2 }
                ]

                delegate: ColumnLayout {
                    id: pointGroup
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 6

                    StyledText {
                        text: pointGroup.modelData.title
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.Medium
                        color: Appearance.colors.colOnLayer1
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        Repeater {
                            model: 2

                            delegate: RowLayout {
                                id: coordinate
                                required property int index
                                readonly property int pointIndex: pointGroup.modelData.xIndex + coordinate.index
                                readonly property bool isX: coordinate.index === 0
                                spacing: 6

                                StyledText {
                                    // Coordinate symbols, not words: not translated.
                                    text: coordinate.isX ? "x" : "y"
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    color: Appearance.colors.colSubtext
                                }

                                SettingsTextField {
                                    id: field
                                    objectName: "curveField:" + coordinate.pointIndex
                                    readonly property real low: coordinate.isX ? CurveMath.X_MIN : CurveMath.Y_MIN
                                    readonly property real high: coordinate.isX ? CurveMath.X_MAX : CurveMath.Y_MAX
                                    readonly property bool inRange: field.valid(field.text)

                                    // Number typed in `text`, or NaN. Handlers call these
                                    // directly: a binding on `text` may still hold the
                                    // previous value inside onTextChanged.
                                    function parse(text) {
                                        const t = String(text).trim().replace(",", ".").replace("−", "-");
                                        return t.length > 0 ? Number(t) : NaN;
                                    }
                                    function valid(text) {
                                        const v = field.parse(text);
                                        return isFinite(v) && v >= field.low && v <= field.high;
                                    }
                                    function stored() {
                                        return root.editedPoints[coordinate.pointIndex].toFixed(2);
                                    }
                                    function commit() {
                                        if (field.valid(field.text))
                                            root.setCoordinate(coordinate.pointIndex, field.parse(field.text), true);
                                        field.text = field.stored();
                                    }

                                    Layout.preferredWidth: 84
                                    enabled: root.enabled
                                    inputMethodHints: Qt.ImhFormattedNumbersOnly
                                    Accessible.name: `${pointGroup.modelData.title} ${coordinate.isX ? "x" : "y"}`
                                    readonly property string hint: coordinate.isX ? Translation.tr("Use a number from 0 to 1") : Translation.tr("Use a number from -1 to 2")
                                    Accessible.description: field.hint
                                    onInvalidChanged: root.setFieldError(coordinate.pointIndex, field.invalid ? field.hint : "")
                                    // Only typed text can be invalid: the editor writes
                                    // stored values while the field has no focus, or
                                    // valid ones (steps, commit) while it has.
                                    invalid: field.activeFocus && !field.inRange
                                    onTextChanged: {
                                        if (field.activeFocus && field.valid(field.text))
                                            root.setCoordinate(coordinate.pointIndex, field.parse(field.text), false);
                                    }
                                    onAccepted: field.commit()
                                    onActiveFocusChanged: if (!field.activeFocus) field.commit()
                                    Keys.onUpPressed: event => {
                                        root.step(coordinate.pointIndex, (event.modifiers & Qt.ShiftModifier) ? 0.1 : 0.01, true);
                                        field.text = field.stored();
                                    }
                                    Keys.onDownPressed: event => {
                                        root.step(coordinate.pointIndex, (event.modifiers & Qt.ShiftModifier) ? -0.1 : -0.01, true);
                                        field.text = field.stored();
                                    }
                                    Component.onCompleted: field.text = field.stored()

                                    Connections {
                                        target: root
                                        function onEditedPointsChanged() {
                                            if (!field.activeFocus)
                                                field.text = field.stored();
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            StyledText {
                Layout.fillWidth: true
                visible: root.invalidMessage.length > 0
                text: root.invalidMessage
                wrapMode: Text.Wrap
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colError
            }
        }
    }

    NumberAnimation {
        id: ballAnimation
        target: root
        property: "ballProgress"
        from: 0
        to: 1
        duration: Math.max(1, root.durationMs) // motion-ok: Hyprland preview
    }
}
