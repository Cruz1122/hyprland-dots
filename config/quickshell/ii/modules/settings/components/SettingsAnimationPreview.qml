import QtQuick
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import "CurveMath.js" as CurveMath

// Miniature screen that shows what one Hyprland animation card does.
//   family     card id: windowsIn, windowsOut, windowsMove, workspaces,
//              specialWorkspaceIn, specialWorkspaceOut, layersIn, layersOut,
//              border, zoomFactor
//   kind, percent, direction
//              the parsed style (AnimationLogic.parseStyle); percent < 0 =
//              not given, direction "" = Hyprland's default
//   durationMs speedToMs(speed); a spring curve ignores it and lasts until
//              Hyprland would end it (CurveMath.springSettleMs)
//   curve      curve descriptor; `enabled` false = the animation is off
//              (the preview shows the end and play() does not move it)
//   reduceMotion
//              replay() (an automatic replay, e.g. after a control is
//              released) does nothing while it is set; play() (the user's
//              explicit ▶) always plays
// When idle the preview shows the END state (the animated element at rest):
// a first frame of an opening animation would be an empty desktop. play()
// and replay() restart from the first frame. Playback is a linear progress
// 0..1 mapped through CurveMath, never a Qt easing curve, so it follows
// Hyprland's own math. It never loops and does not follow the shell motion
// scale.
Item {
    id: root

    property string family: "windowsIn"
    property string kind: "popin"
    property real percent: -1
    property string direction: ""
    property real durationMs: 300
    property var curve: ({ name: "default", type: "bezier", points: CurveMath.DEFAULT_POINTS })
    property bool reduceMotion: false
    property real progress: 1
    readonly property bool isSpring: CurveMath.isSpring(root.curve)
    readonly property real effectiveDurationMs: root.isSpring ? CurveMath.springSettleMs(root.curve) : Math.max(1, root.durationMs)
    readonly property real value: CurveMath.valueAt(root.curve, root.progress, root.effectiveDurationMs)
    readonly property bool playing: progressAnimation.running
    readonly property string group: {
        switch (root.family) {
        case "windowsIn":
        case "windowsOut":
            return "window";
        case "windowsMove":
            return "move";
        case "workspaces":
            return "workspace";
        case "specialWorkspaceIn":
        case "specialWorkspaceOut":
            return "special";
        case "layersIn":
        case "layersOut":
            return "layer";
        case "border":
            return "border";
        case "zoomFactor":
            return "zoom";
        }
        return "window";
    }
    readonly property bool closing: root.family.endsWith("Out")

    // Explicit play (▶): plays even with reduceMotion; a disabled animation
    // only shows its end.
    function play() {
        progressAnimation.stop();
        if (!root.enabled) {
            root.progress = 1;
            return;
        }
        root.progress = 0;
        progressAnimation.start();
    }

    // Automatic replay (a value changed, a slider was released): nothing
    // moves while reduceMotion is set.
    function replay() {
        if (root.reduceMotion)
            return;
        root.play();
    }

    // Shows a fixed frame (harness, tests): linear progress in [0, 1].
    function seek(linearProgress) {
        progressAnimation.stop();
        root.progress = Math.max(0, Math.min(1, linearProgress));
    }

    function lerp(a, b, t) {
        return a + (b - a) * t;
    }

    function clamp01(v) {
        return Math.max(0, Math.min(1, v));
    }

    function mixColor(a, b, t) {
        const k = root.clamp01(t);
        return Qt.rgba(root.lerp(a.r, b.r, k), root.lerp(a.g, b.g, k), root.lerp(a.b, b.b, k), root.lerp(a.a, b.a, k));
    }

    implicitWidth: 260
    implicitHeight: Math.round((root.width > 0 ? root.width : root.implicitWidth) * 0.625)
    Accessible.role: Accessible.Animation
    Accessible.name: Translation.tr("Animation preview")

    onFamilyChanged: root.seek(1)
    onEnabledChanged: if (!root.enabled) root.seek(1)

    NumberAnimation {
        id: progressAnimation
        target: root
        property: "progress"
        from: 0
        to: 1
        duration: root.effectiveDurationMs // motion-ok: Hyprland preview
    }

    // Mock surfaces use the opaque m3 colours: the colLayer* colours are
    // translucent and would show what is behind them.
    component MockWindow: Rectangle {
        id: mock
        property color accent: Appearance.colors.colPrimary
        property bool active: true

        radius: Math.min(8, mock.height / 4)
        color: Appearance.m3colors.m3surfaceContainerHigh
        border.width: mock.height > 6 ? 2 : 0
        border.color: mock.active ? mock.accent : Appearance.colors.colOutlineVariant
        clip: true

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 2
            implicitHeight: Math.max(0, Math.min(10, mock.height * 0.16))
            radius: Math.min(6, mock.height / 8)
            color: Appearance.m3colors.m3surfaceContainerHighest
        }

        Column {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            anchors.topMargin: Math.min(10, mock.height * 0.16) + 8
            spacing: 5
            visible: mock.height > 40 && mock.width > 40

            Repeater {
                model: [0.85, 0.6, 0.72]

                delegate: Rectangle {
                    required property real modelData
                    implicitWidth: (mock.width - 16) * modelData
                    implicitHeight: 4
                    radius: 2
                    color: Appearance.colors.colOutlineVariant
                }
            }
        }
    }

    component Workspace: Item {
        id: ws
        property string number: "1"
        property color accent: Appearance.colors.colPrimary
        // Two tiled windows, or one window filling the workspace, so two
        // workspaces look different even in a monochrome theme.
        property bool split: true
        readonly property real gap: Math.max(4, ws.width * 0.02)
        readonly property real topInset: ws.height * 0.12

        MockWindow {
            id: mainWindow
            x: ws.gap
            y: ws.topInset
            implicitWidth: ws.split ? ws.width * 0.5 - ws.gap * 1.5 : ws.width - ws.gap * 2
            implicitHeight: ws.height - ws.topInset - ws.gap
            accent: ws.accent
        }

        MockWindow {
            visible: ws.split
            x: ws.width * 0.5 + ws.gap * 0.5
            y: ws.topInset
            implicitWidth: ws.width * 0.5 - ws.gap * 1.5
            implicitHeight: ws.height - ws.topInset - ws.gap
            active: false
        }

        // The workspace number, large in the main window, tells the two
        // workspaces apart while they slide.
        StyledText {
            anchors.centerIn: mainWindow
            anchors.verticalCenterOffset: mainWindow.height * 0.12
            // Workspace numbers, not words: not translated.
            text: ws.number
            font.pixelSize: Math.max(10, Math.round(ws.height * 0.18))
            font.weight: Font.Bold
            color: ws.accent
            opacity: 0.7
        }
    }

    // The bezel: the rounded frame. The mini screen inside is clipped to a
    // rectangle inset far enough that its square corners stay inside the
    // rounded border (a rounded clip would need a shader mask, which the
    // software renderer does not draw), and the border is drawn above it.
    Rectangle {
        id: bezel
        anchors.fill: parent
        radius: SettingsMetrics.controlRadius
        color: Appearance.m3colors.m3surfaceContainerHigh
    }

    Rectangle {
        id: screen
        objectName: "previewScreen"
        readonly property real inset: Math.ceil(bezel.radius * (1 - Math.SQRT1_2)) + frame.border.width + 1
        anchors.fill: parent
        anchors.margins: screen.inset
        color: Appearance.colors.colLayer0Base
        clip: true

        readonly property real sw: screen.width
        readonly property real sh: screen.height
        // Geometry of the window the window families animate.
        readonly property real gw: screen.sw * 0.46
        readonly property real gh: screen.sh * 0.52
        readonly property real gx: (screen.sw - screen.gw) / 2
        readonly property real gy: screen.sh * 0.26

        // Wallpaper-like backdrop.
        gradient: Gradient {
            GradientStop { position: 0; color: Appearance.m3colors.m3surfaceContainerLowest }
            GradientStop { position: 1; color: Appearance.m3colors.m3surfaceContainerLow }
        }

        Item {
            id: zoomLayer
            anchors.fill: parent
            transformOrigin: Item.Center
            scale: root.group === "zoom" ? root.lerp(1, 1.5, root.value) : 1
            readonly property real cursorX: screen.sw * 0.66
            readonly property real cursorY: screen.sh * 0.58
            transform: Translate {
                // Zoom around the cursor instead of the centre.
                x: root.group === "zoom" ? (zoomLayer.width / 2 - zoomLayer.cursorX) * (zoomLayer.scale - 1) : 0
                y: root.group === "zoom" ? (zoomLayer.height / 2 - zoomLayer.cursorY) * (zoomLayer.scale - 1) : 0
            }

            // Shell bar.
            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 4
                implicitHeight: Math.max(6, screen.sh * 0.06)
                radius: implicitHeight / 2
                color: Appearance.m3colors.m3surfaceContainerHighest
                z: 5
            }

            // windowsIn / windowsOut: the style decides where the window
            // comes from; the fade companion follows the progress.
            MockWindow {
                id: openingWindow
                objectName: "previewWindow"
                readonly property real p: root.closing ? 1 - root.value : root.value
                readonly property real minPerc: root.percent >= 0 ? root.percent / 100 : 0
                readonly property string slideFrom: {
                    if (root.direction.length > 0)
                        return root.direction;
                    // Nearest monitor edge to the window's centre (ties: bottom
                    // first, as WindowAnimationController::applySlide).
                    const mx = screen.gx + screen.gw / 2;
                    const my = screen.gy + screen.gh / 2;
                    const d = { top: my, right: screen.sw - mx, bottom: screen.sh - my, left: mx };
                    const m = Math.min(d.top, d.right, d.bottom, d.left);
                    return m === d.bottom ? "bottom" : m === d.left ? "left" : m === d.right ? "right" : "top";
                }
                readonly property var from: {
                    switch (root.kind) {
                    case "slide": {
                        const offsets = {
                            top: [screen.gx, -screen.gh],
                            bottom: [screen.gx, screen.sh],
                            left: [screen.gx - screen.gw, screen.gy],
                            right: [screen.gx + screen.gw, screen.gy]
                        };
                        const o = offsets[openingWindow.slideFrom] ?? offsets.top;
                        return { x: o[0], y: o[1], w: screen.gw, h: screen.gh };
                    }
                    case "gnomed":
                        return { x: screen.gx, y: screen.gy + screen.gh / 2, w: screen.gw, h: 0 };
                    default: {
                        // popin: Hyprland's 5 px minimum, scaled to the preview.
                        const w = Math.max(2, screen.gw * openingWindow.minPerc);
                        const h = Math.max(2, screen.gh * openingWindow.minPerc);
                        return { x: screen.gx + (screen.gw - w) / 2, y: screen.gy + (screen.gh - h) / 2, w: w, h: h };
                    }
                    }
                }

                visible: root.group === "window"
                x: root.lerp(openingWindow.from.x, screen.gx, openingWindow.p)
                y: root.lerp(openingWindow.from.y, screen.gy, openingWindow.p)
                implicitWidth: Math.max(0, root.lerp(openingWindow.from.w, screen.gw, openingWindow.p))
                implicitHeight: Math.max(0, root.lerp(openingWindow.from.h, screen.gh, openingWindow.p))
                opacity: root.clamp01(openingWindow.p)
            }

            // windowsMove: a tiled window swaps to the other half.
            MockWindow {
                id: movingWindow
                readonly property real w: screen.sw * 0.44
                visible: root.group === "move"
                x: root.lerp(screen.sw * 0.04, screen.sw * 0.52, root.value)
                y: screen.sh * 0.16
                implicitWidth: movingWindow.w
                implicitHeight: screen.sh * 0.78
            }

            Rectangle {
                visible: root.group === "move"
                x: screen.sw * 0.52
                y: screen.sh * 0.16
                implicitWidth: movingWindow.w
                implicitHeight: screen.sh * 0.78
                radius: 8
                color: "transparent"
                border.width: 1
                border.color: Appearance.colors.colOutline
                opacity: 0.6
            }

            // workspaces and specialWorkspace*: Hyprland's
            // WorkspaceAnimationController offsets and alpha.
            Item {
                id: workspaces
                anchors.fill: parent
                visible: root.group === "workspace" || root.group === "special"

                readonly property bool vertical: root.direction === "top" || root.direction === "bottom"
                    || (root.direction.length === 0 && (root.kind === "slidevert" || root.kind === "slidefadevert"))
                // Hyprland's `left`: the incoming workspace comes from the
                // right (or the bottom), as when moving to a higher number.
                readonly property bool fromFar: root.direction.length > 0 ? (root.direction === "right" || root.direction === "bottom") : true
                readonly property bool fades: root.kind === "fade" || root.kind === "slidefade" || root.kind === "slidefadevert" || root.group === "special"
                readonly property bool moves: root.kind !== "fade"
                readonly property real perc: root.percent >= 0 ? root.percent / 100 : 1
                readonly property real distance: {
                    const size = workspaces.vertical ? screen.sh : screen.sw;
                    // slide/slidevert add general:gaps_workspaces (0 here).
                    return size * workspaces.perc * (workspaces.fromFar ? 1 : -1);
                }
                // Incoming workspace (or the special workspace) progress.
                readonly property real p: root.group === "special" && root.closing ? 1 - root.value : root.value

                Workspace {
                    id: currentWorkspace
                    objectName: "previewCurrentWorkspace"
                    anchors.fill: parent
                    number: "1"
                    visible: root.group === "workspace"
                    transform: Translate {
                        x: !workspaces.vertical && workspaces.moves ? -workspaces.distance * root.value : 0
                        y: workspaces.vertical && workspaces.moves ? -workspaces.distance * root.value : 0
                    }
                    opacity: workspaces.fades ? root.clamp01(1 - root.value) : 1
                }

                Workspace {
                    objectName: "previewIncomingWorkspace"
                    anchors.fill: parent
                    number: "2"
                    split: false
                    accent: Appearance.colors.colTertiary
                    visible: root.group === "workspace"
                    transform: Translate {
                        x: !workspaces.vertical && workspaces.moves ? workspaces.distance * (1 - root.value) : 0
                        y: workspaces.vertical && workspaces.moves ? workspaces.distance * (1 - root.value) : 0
                    }
                    opacity: workspaces.fades ? root.clamp01(root.value) : 1
                }

                // The special workspace slides over the current one, which
                // stays put and dims.
                Workspace {
                    anchors.fill: parent
                    number: "1"
                    visible: root.group === "special"
                }

                Rectangle {
                    anchors.fill: parent
                    visible: root.group === "special"
                    color: Appearance.colors.colScrim
                    opacity: root.clamp01(workspaces.p) * 0.6
                }

                Item {
                    anchors.fill: parent
                    visible: root.group === "special"
                    opacity: root.clamp01(workspaces.p)
                    transform: Translate {
                        x: !workspaces.vertical && workspaces.moves ? workspaces.distance * (1 - workspaces.p) : 0
                        y: workspaces.vertical && workspaces.moves ? workspaces.distance * (1 - workspaces.p) : 0
                    }

                    MockWindow {
                        x: screen.sw * 0.14
                        y: screen.sh * 0.18
                        implicitWidth: screen.sw * 0.72
                        implicitHeight: screen.sh * 0.68
                        accent: Appearance.colors.colTertiary
                    }
                }
            }

            // layersIn / layersOut: a shell panel enters from its screen
            // edge (rules.lua gives most panels their own style, so only the
            // duration and the curve matter here).
            Item {
                anchors.fill: parent
                visible: root.group === "layer"

                Workspace {
                    anchors.fill: parent
                    number: "1"
                }

                Rectangle {
                    id: panel
                    readonly property real p: root.closing ? 1 - root.value : root.value
                    readonly property real w: screen.sw * 0.32
                    readonly property real restX: screen.sw - panel.w - 6
                    x: root.lerp(screen.sw, panel.restX, panel.p)
                    y: screen.sh * 0.12
                    implicitWidth: panel.w
                    implicitHeight: screen.sh * 0.84
                    radius: 10
                    color: Appearance.m3colors.m3surfaceContainer
                    border.width: 1
                    border.color: Appearance.colors.colOutlineVariant
                    opacity: root.clamp01(panel.p)

                    Column {
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 6

                        Repeater {
                            model: 4

                            delegate: Rectangle {
                                implicitWidth: panel.w - 16
                                implicitHeight: 12
                                radius: 6
                                color: Appearance.m3colors.m3surfaceContainerHighest
                            }
                        }
                    }
                }
            }

            // border: focus moves to the right window; the active colour
            // fades from one border to the other.
            Item {
                anchors.fill: parent
                visible: root.group === "border"

                Repeater {
                    model: 2

                    delegate: MockWindow {
                        required property int index
                        readonly property real gap: Math.max(4, screen.sw * 0.02)
                        x: index === 0 ? gap : screen.sw * 0.5 + gap * 0.5
                        y: screen.sh * 0.12
                        implicitWidth: screen.sw * 0.5 - gap * 1.5
                        implicitHeight: screen.sh * 0.88 - gap
                        active: true
                        border.width: 3
                        border.color: index === 0
                            ? root.mixColor(Appearance.colors.colPrimary, Appearance.colors.colOutlineVariant, root.value)
                            : root.mixColor(Appearance.colors.colOutlineVariant, Appearance.colors.colPrimary, root.value)
                    }
                }
            }

            // zoomFactor: the whole screen zooms in around the cursor.
            Workspace {
                anchors.fill: parent
                number: "1"
                visible: root.group === "zoom"
            }

            MaterialSymbol {
                visible: root.group === "zoom"
                x: zoomLayer.cursorX - 4
                y: zoomLayer.cursorY - 4
                text: "arrow_selector_tool"
                iconSize: 16
                color: Appearance.colors.colOnLayer0
                z: 6
            }
        }
    }

    Rectangle {
        id: frame
        objectName: "previewFrame"
        anchors.fill: parent
        radius: bezel.radius
        color: "transparent"
        border.width: 1
        border.color: Appearance.colors.colOutlineVariant
    }

    Row {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: screen.inset + 4
        spacing: 4

        PreviewChip {
            visible: !root.enabled
            text: Translation.tr("No animation")
        }

        PreviewChip {
            visible: root.enabled && root.isSpring
            text: Translation.tr("Approximate")
        }
    }

    component PreviewChip: Rectangle {
        id: chip
        property alias text: chipText.text
        implicitWidth: chipText.implicitWidth + 12
        implicitHeight: chipText.implicitHeight + 4
        radius: chip.implicitHeight / 2
        color: Appearance.colors.colSecondaryContainer

        StyledText {
            id: chipText
            anchors.centerIn: parent
            font.pixelSize: Appearance.font.pixelSize.smallest
            color: Appearance.colors.colOnSecondaryContainer
        }
    }
}
