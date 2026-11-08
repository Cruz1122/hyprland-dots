import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs.modules.settings.core
import "WindowPreviewLogic.js" as PreviewLogic

// Mini desktop drawn from the Windows page's current values (docs/settings.md
// "Windows preview and system checks"): dwindle tiles with gaps, border,
// rounding and rounding power, the floating window's shadow, opacity, blur
// behind the bar and a panel, and dimming (exaggerated, and said so). With
// `showMagnifier`, a 1:1 crop of one window corner shows the real pixel sizes.
// `highlightKey` (the page's focused or hovered row) outlines the part that
// row changes. Static drawing: it repaints only when a value, the theme or the
// highlight changes, so there is nothing to animate.
ColumnLayout {
    id: preview
    objectName: "windowPreview"

    property bool showMagnifier: true
    property string highlightKey: ""
    // What screen readers hear for the drawing: each instance names the
    // part it is about (layoutSummary or effectsSummary).
    property string accessibleName: Translation.tr("Preview")
    property string accessibleDescription: preview.layoutSummary
    readonly property string highlightPart: PreviewLogic.partForKey(preview.highlightKey)

    readonly property var raw: {
        void SettingsStore.revision;
        const out = {};
        for (const name in PreviewLogic.VALUE_KEYS)
            out[name] = SettingsStore.value(PreviewLogic.VALUE_KEYS[name]);
        return out;
    }
    readonly property string layoutSummary: Translation.tr("Gaps %1 px and %2 px at the edges, border %3 px, corner radius %4 px")
        .arg(preview.model.values.gapsIn).arg(preview.model.values.gapsOut)
        .arg(preview.model.values.border).arg(preview.model.values.rounding)
    readonly property string effectsSummary: {
        const v = preview.model.values;
        return [
            v.blur ? Translation.tr("Blur behind the bar and panels: %1 px, %2 passes").arg(Math.round(v.blurSize)).arg(v.blurPasses)
                : Translation.tr("No blur behind the bar and panels"),
            v.shadow ? Translation.tr("Shadow of floating windows: %1 px").arg(Math.round(v.shadowRange))
                : Translation.tr("No shadow on floating windows"),
            Translation.tr("Opacity: %1 % for the active window, %2 % for the others")
                .arg(Math.round(v.activeOpacity * 100)).arg(Math.round(v.inactiveOpacity * 100)),
            v.dim ? Translation.tr("Inactive windows dimmed by %1 %").arg(Math.round(v.dimStrength * 100))
                : Translation.tr("Inactive windows are not dimmed")
        ].join(". ");
    }
    readonly property bool wide: preview.width >= 540
    readonly property real desktopWidth: Math.max(160, desktopBox.width)
    readonly property var model: PreviewLogic.desktop(preview.raw, preview.desktopWidth)
    readonly property int magnifierWidth: 184
    readonly property int magnifierHeight: 150
    readonly property int anchorX: 78
    readonly property int anchorY: 76
    readonly property var lens: PreviewLogic.magnifier(preview.raw, preview.magnifierWidth, preview.magnifierHeight, preview.anchorX, preview.anchorY)

    // Border colours from Hyprland (the dotfiles' matugen colours), read once;
    // the theme's colours stand in until then or without Hyprland.
    readonly property bool hyprland: (Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") ?? "").length > 0
    property string activeBorderHex: ""
    property string inactiveBorderHex: ""
    readonly property color activeBorder: preview.activeBorderHex.length > 0 ? preview.activeBorderHex : Appearance.colors.colPrimary
    readonly property color inactiveBorder: preview.inactiveBorderHex.length > 0 ? preview.inactiveBorderHex : Appearance.colors.colOutlineVariant

    // Theme layers can be translucent; the sketch's surfaces are opaque.
    readonly property color wallpaperColor: Qt.alpha(Appearance.colors.colLayer0, 1)
    readonly property color windowColor: Qt.alpha(Appearance.colors.colLayer1, 1)
    onWallpaperColorChanged: preview.repaint()
    onWindowColorChanged: preview.repaint()

    // Wallpaper of the sketch, in virtual screen pixels (1280×800).
    readonly property var blobs: [
        { x: 180, y: 620, r: 330, color: Appearance.colors.colPrimaryContainer },
        { x: 1040, y: 160, r: 300, color: Appearance.colors.colTertiaryContainer },
        { x: 760, y: 700, r: 220, color: Appearance.colors.colSecondaryContainer }
    ]

    function repaint() {
        desktopCanvas.requestPaint();
        lensCanvas.requestPaint();
    }

    onModelChanged: preview.repaint()
    onLensChanged: preview.repaint()
    onHighlightPartChanged: preview.repaint()
    onActiveBorderChanged: preview.repaint()
    onInactiveBorderChanged: preview.repaint()
    onBlobsChanged: preview.repaint()

    spacing: 8

    Process {
        running: preview.hyprland
        command: ["hyprctl", "-j", "getoption", "general:col.active_border"]
        stdout: StdioCollector {
            id: activeOut
            onStreamFinished: preview.activeBorderHex = PreviewLogic.borderColor(activeOut.text)
        }
    }

    Process {
        running: preview.hyprland
        command: ["hyprctl", "-j", "getoption", "general:col.inactive_border"]
        stdout: StdioCollector {
            id: inactiveOut
            onStreamFinished: preview.inactiveBorderHex = PreviewLogic.borderColor(inactiveOut.text)
        }
    }

    // ------------------------------------------------------------ drawing

    function tracePath(ctx, box, radius, power) {
        const points = PreviewLogic.roundedRectPoints(box, radius, power, 10);
        ctx.moveTo(points[0].x, points[0].y);
        for (let i = 1; i < points.length; i++)
            ctx.lineTo(points[i].x, points[i].y);
        ctx.closePath();
    }

    function drawWallpaper(ctx, scale, softness) {
        ctx.fillStyle = preview.wallpaperColor;
        ctx.fillRect(0, 0, PreviewLogic.SCREEN_WIDTH * scale, PreviewLogic.SCREEN_HEIGHT * scale);
        for (const blob of preview.blobs) {
            const r = blob.r * scale;
            const soft = Math.min(softness, r);
            if (soft <= 0) {
                ctx.beginPath();
                ctx.arc(blob.x * scale, blob.y * scale, r, 0, 2 * Math.PI);
                ctx.fillStyle = blob.color;
                ctx.fill();
                continue;
            }
            const gradient = ctx.createRadialGradient(blob.x * scale, blob.y * scale, 0, blob.x * scale, blob.y * scale, r + soft / 2);
            gradient.addColorStop(0, blob.color);
            gradient.addColorStop(Math.max(0, (r - soft / 2) / (r + soft / 2)), blob.color);
            gradient.addColorStop(1, Qt.alpha(blob.color, 0));
            ctx.fillStyle = gradient;
            ctx.fillRect(0, 0, PreviewLogic.SCREEN_WIDTH * scale, PreviewLogic.SCREEN_HEIGHT * scale);
        }
    }

    // A window: border ring, content and a few placeholder lines, at the
    // window's opacity; inactive windows get the (exaggerated) dim.
    function drawWindow(ctx, w, power, opacity, dim, borderColor) {
        ctx.save();
        ctx.globalAlpha = opacity;
        if (w.border > 0) {
            ctx.beginPath();
            preview.tracePath(ctx, w.box, w.outerRadius, power);
            preview.tracePath(ctx, w.content, w.radius, power);
            ctx.fillRule = Qt.OddEvenFill;
            ctx.fillStyle = borderColor;
            ctx.fill();
            ctx.fillRule = Qt.WindingFill;
        }
        ctx.beginPath();
        preview.tracePath(ctx, w.content, w.radius, power);
        ctx.fillStyle = preview.windowColor;
        ctx.fill();
        ctx.save();
        ctx.clip();
        ctx.fillStyle = Qt.alpha(Appearance.colors.colOnLayer1, 0.14);
        const pad = Math.max(4, w.content.width * 0.06);
        const line = Math.max(2, w.content.height * 0.035);
        for (let i = 0; i < 4; i++) {
            const y = w.content.y + pad + i * line * 2.4;
            if (y + line > w.content.y + w.content.height - pad)
                break;
            ctx.fillRect(w.content.x + pad, y, (w.content.width - 2 * pad) * (i === 0 ? 0.45 : 0.9 - i * 0.12), line);
        }
        if (dim > 0) {
            ctx.fillStyle = Qt.rgba(0, 0, 0, dim);
            ctx.fillRect(w.box.x, w.box.y, w.box.width, w.box.height);
        }
        ctx.restore();
        ctx.restore();
    }

    function strokeHighlight(ctx, box, radius, power) {
        ctx.beginPath();
        preview.tracePath(ctx, box, radius, power);
        ctx.lineWidth = 2;
        ctx.strokeStyle = Appearance.colors.colPrimary;
        ctx.stroke();
    }

    function paintDesktop(ctx) {
        const m = preview.model;
        const v = m.values;
        const s = m.scale;
        const p = v.roundingPower;
        ctx.reset();
        ctx.save();
        ctx.beginPath();
        preview.tracePath(ctx, { x: 0, y: 0, width: m.width, height: m.height }, 10, 2);
        ctx.clip();
        preview.drawWallpaper(ctx, s, 0);

        // Tiled windows (the main one is active) and the floating one.
        const main = m.tiled[0];
        for (const w of m.tiled)
            preview.drawWindow(ctx, w, p, w.active ? v.activeOpacity : v.inactiveOpacity, w.active ? 0 : m.dim,
                w.active ? preview.activeBorder : preview.inactiveBorder);
        const f = m.floating;
        if (m.shadowBlur > 0) {
            ctx.save();
            ctx.shadowColor = Qt.rgba(0, 0, 0, 0.5);
            ctx.shadowBlur = m.shadowBlur;
            ctx.shadowOffsetY = 2 * s;
            ctx.beginPath();
            preview.tracePath(ctx, f.box, f.outerRadius, p);
            ctx.fillStyle = preview.windowColor;
            ctx.fill();
            ctx.restore();
        }
        preview.drawWindow(ctx, f, p, v.inactiveOpacity, m.dim, preview.inactiveBorder);

        // The bar and a panel: with blur they show the wallpaper softened
        // (the dotfiles' layer rules use xray, so not the windows below).
        for (const surface of [{ box: m.bar, radius: 0 }, { box: m.panel, radius: 14 * s + 2 }]) {
            ctx.save();
            ctx.beginPath();
            preview.tracePath(ctx, surface.box, surface.radius, 2);
            ctx.clip();
            if (m.blurRadius > 0)
                preview.drawWallpaper(ctx, s, m.blurRadius);
            ctx.fillStyle = Qt.alpha(Appearance.colors.colLayer0, 0.55);
            ctx.fillRect(surface.box.x, surface.box.y, surface.box.width, surface.box.height);
            ctx.restore();
        }
        ctx.fillStyle = Qt.alpha(Appearance.colors.colOnLayer0, 0.5);
        for (let i = 0; i < 5; i++) {
            ctx.beginPath();
            ctx.arc(m.width / 2 + (i - 2) * 26 * s, m.bar.height / 2, Math.max(1.5, 6 * s), 0, 2 * Math.PI);
            ctx.fill();
        }
        ctx.fillStyle = Qt.alpha(Appearance.colors.colOnLayer0, 0.3);
        ctx.fillRect(m.panel.x + 18 * s, m.panel.y + 22 * s, m.panel.width * 0.55, Math.max(2, 14 * s));
        ctx.fillRect(m.panel.x + 18 * s, m.panel.y + 52 * s, m.panel.width * 0.75, Math.max(2, 10 * s));

        // Highlight of the focused or hovered row's part.
        const part = preview.highlightPart;
        ctx.fillStyle = Qt.alpha(Appearance.colors.colPrimary, 0.6);
        if (part === "gapsIn") {
            const right = m.tiled[1];
            ctx.fillRect(main.box.x + main.box.width, main.box.y, right.box.x - main.box.x - main.box.width, main.box.height);
            ctx.fillRect(right.box.x, right.box.y + right.box.height, right.box.width, m.tiled[2].box.y - right.box.y - right.box.height);
        } else if (part === "gapsOut") {
            const g = v.gapsOut * s;
            ctx.fillRect(0, m.bar.height, m.width, g);
            ctx.fillRect(0, m.height - g, m.width, g);
            ctx.fillRect(0, m.bar.height, g, m.height - m.bar.height);
            ctx.fillRect(m.width - g, m.bar.height, g, m.height - m.bar.height);
        } else if (part === "border" || part === "rounding" || part === "roundingPower") {
            for (const w of m.tiled)
                preview.strokeHighlight(ctx, w.box, w.outerRadius, p);
        } else if (part === "blur") {
            preview.strokeHighlight(ctx, m.bar, 0, 2);
            preview.strokeHighlight(ctx, m.panel, 14 * s + 2, 2);
        } else if (part === "shadow") {
            const r = f.shadowRange;
            preview.strokeHighlight(ctx, { x: f.box.x - r, y: f.box.y - r, width: f.box.width + 2 * r, height: f.box.height + 2 * r }, f.outerRadius + r, 2);
        } else if (part === "dim" || part === "inactiveOpacity") {
            for (const w of m.tiled.slice(1).concat([f]))
                preview.strokeHighlight(ctx, w.box, w.outerRadius, p);
        } else if (part === "activeOpacity") {
            preview.strokeHighlight(ctx, main.box, main.outerRadius, p);
        }
        ctx.restore();
    }

    function measure(ctx, x1, y1, x2, y2, on) {
        ctx.save();
        ctx.strokeStyle = on ? Appearance.colors.colPrimary : Qt.alpha(Appearance.colors.colOnLayer1, 0.6);
        ctx.fillStyle = ctx.strokeStyle;
        ctx.lineWidth = on ? 2 : 1;
        ctx.beginPath();
        ctx.moveTo(x1, y1);
        ctx.lineTo(x2, y2);
        ctx.stroke();
        // End ticks across the line.
        const vertical = x1 === x2;
        for (const [x, y] of [[x1, y1], [x2, y2]]) {
            ctx.beginPath();
            ctx.moveTo(vertical ? x - 4 : x, vertical ? y : y - 4);
            ctx.lineTo(vertical ? x + 4 : x, vertical ? y : y + 4);
            ctx.stroke();
        }
        ctx.restore();
    }

    function paintLens(ctx) {
        const l = preview.lens;
        const v = l.values;
        const p = v.roundingPower;
        const part = preview.highlightPart;
        ctx.reset();
        ctx.fillStyle = preview.wallpaperColor;
        ctx.fillRect(0, 0, l.width, l.height);
        ctx.fillStyle = Appearance.colors.colSurfaceContainerHigh;
        ctx.fillRect(l.bar.x, l.bar.y, l.bar.width, l.bar.height);
        for (const w of [l.main, l.neighbor])
            preview.drawWindow(ctx, w, p, 1, 0, w.active ? preview.activeBorder : preview.inactiveBorder);
        if (part === "border" && l.main.border > 0) {
            ctx.save();
            ctx.beginPath();
            preview.tracePath(ctx, l.main.box, l.main.outerRadius, p);
            preview.tracePath(ctx, l.main.content, l.main.radius, p);
            ctx.fillRule = Qt.OddEvenFill;
            ctx.fillStyle = Appearance.colors.colPrimary;
            ctx.fill();
            ctx.restore();
        }
        if ((part === "rounding" || part === "roundingPower") && l.main.radius > 0) {
            // The quarter circle (power 2) dashed, the real curve solid.
            const box = l.main.content;
            ctx.save();
            ctx.beginPath();
            ctx.rect(box.x + box.width - l.main.radius - 1, box.y - 1, l.main.radius + 2, l.main.radius + 2);
            ctx.clip();
            ctx.lineWidth = 2;
            ctx.strokeStyle = Appearance.colors.colPrimary;
            ctx.beginPath();
            preview.tracePath(ctx, box, l.main.radius, p);
            ctx.stroke();
            ctx.setLineDash([3, 3]);
            ctx.lineWidth = 1;
            ctx.strokeStyle = Appearance.colors.colOnLayer1;
            ctx.beginPath();
            preview.tracePath(ctx, box, l.main.radius, 2);
            ctx.stroke();
            ctx.restore();
        }
        const edgeX = preview.anchorX - Math.max(28, l.main.outerRadius + 10);
        if (v.gapsOut > 0)
            preview.measure(ctx, edgeX, preview.anchorY - v.gapsOut, edgeX, preview.anchorY, part === "gapsOut");
        const gapY = preview.anchorY + Math.max(34, l.main.outerRadius + 10);
        if (v.gapsIn > 0)
            preview.measure(ctx, preview.anchorX, gapY, preview.anchorX + 2 * v.gapsIn, gapY, part === "gapsIn");
        ctx.strokeStyle = Appearance.colors.colOutlineVariant;
        ctx.lineWidth = 1;
        ctx.strokeRect(0.5, 0.5, l.width - 1, l.height - 1);
    }

    // ------------------------------------------------------------ layout

    GridLayout {
        Layout.fillWidth: true
        columns: preview.wide && preview.showMagnifier ? 2 : 1
        columnSpacing: 16
        rowSpacing: 10

        Item {
            id: desktopBox
            Layout.fillWidth: true
            Layout.maximumWidth: 560
            Layout.alignment: Qt.AlignTop
            implicitWidth: 320
            implicitHeight: desktopBox.width * PreviewLogic.SCREEN_HEIGHT / PreviewLogic.SCREEN_WIDTH

            Canvas {
                id: desktopCanvas
                objectName: "windowPreviewDesktop"
                anchors.fill: parent
                onPaint: preview.paintDesktop(desktopCanvas.getContext("2d"))
                onWidthChanged: desktopCanvas.requestPaint()
                Accessible.role: Accessible.Graphic
                Accessible.name: preview.accessibleName
                Accessible.description: preview.accessibleDescription
            }
        }

        ColumnLayout {
            visible: preview.showMagnifier
            Layout.alignment: Qt.AlignTop
            spacing: 6

            StyledText {
                text: Translation.tr("Corner at real size")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }

            Canvas {
                id: lensCanvas
                objectName: "windowPreviewMagnifier"
                implicitWidth: preview.magnifierWidth
                implicitHeight: preview.magnifierHeight
                onPaint: preview.paintLens(lensCanvas.getContext("2d"))
                Accessible.role: Accessible.Graphic
                Accessible.name: Translation.tr("Corner at real size")
            }

            Repeater {
                model: [
                    { part: "gapsOut", text: Translation.tr("Screen edge: %1 px").arg(preview.lens.values.gapsOut) },
                    { part: "gapsIn", text: Translation.tr("Between windows: 2 × %1 px").arg(preview.lens.values.gapsIn) },
                    { part: "border", text: Translation.tr("Border: %1 px").arg(preview.lens.values.border) },
                    { part: "rounding", text: Translation.tr("Radius: %1 px, curve %2").arg(preview.lens.rounding.size)
                        .arg(Number(preview.lens.values.roundingPower).toLocaleString(Qt.locale(), "f", 1)) }
                ]

                delegate: StyledText {
                    required property var modelData
                    readonly property bool on: preview.highlightPart === modelData.part
                        || (modelData.part === "rounding" && preview.highlightPart === "roundingPower")
                    objectName: "magnifierLabel:" + modelData.part
                    text: modelData.text
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.weight: on ? Font.DemiBold : Font.Normal
                    color: on ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer1
                }
            }
        }
    }

    StyledText {
        objectName: "windowPreviewNote"
        Layout.fillWidth: true
        visible: text.length > 0
        text: [
            preview.model.values.known ? "" : Translation.tr("Hyprland is not running: the preview uses example values."),
            preview.model.dim > 0 ? Translation.tr("Dimming is exaggerated here so you can see it.") : ""
        ].filter(t => t.length > 0).join(" ")
        wrapMode: Text.Wrap
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: Appearance.colors.colSubtext
    }
}
