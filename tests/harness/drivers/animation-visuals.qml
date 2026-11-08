//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
//@ pragma Env QT_SCALE_FACTOR=1

// Harness driver (run.sh --driver): renders a gallery of the animation
// visuals (SettingsCurveThumb, SettingsCurvePicker, SettingsCurveEditor,
// SettingsAnimationPreview) at 760 and 1100 px in the dark fixture theme and
// a light theme, then checks the picker's keyboard navigation, the editor's
// clamping and validation, and plays one preview to its end. Screenshots
// are "page" reports (overflowX lists clipped text and items past the
// window edge); every check is a "check" report, and a failed one is also
// "fatal" so summarize.py fails the run. tests/test_animation_visuals.py runs it.
import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import QtTest
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
// @harness-imports
import "modules/settings/components/CurveMath.js" as CurveMath

ShellRoot {
    id: root

    readonly property string outDir: Quickshell.env("SHOT_DIR") || ""
    readonly property var widths: [760, 1100]
    readonly property var sections: ["thumbs", "picker", "editor", "previews-end", "previews-mid"]

    readonly property var dotfilesCurves: [
        { name: "default", type: "bezier", points: CurveMath.DEFAULT_POINTS, label: "Hyprland standard", group: "hyprland", builtin: true },
        { name: "linear", type: "bezier", points: CurveMath.LINEAR_POINTS, label: "Constant", group: "hyprland", builtin: true },
        { name: "emphasizedDecel", type: "bezier", points: [0.05, 0.7, 0.1, 1], label: "Quick start, gentle stop", group: "dotfiles", builtin: true },
        { name: "emphasizedAccel", type: "bezier", points: [0.3, 0, 0.8, 0.15], label: "Speeding exit", group: "dotfiles", builtin: true },
        { name: "standardDecel", type: "bezier", points: [0, 0, 0, 1], label: "Standard stop", group: "dotfiles", builtin: true },
        { name: "menu_decel", type: "bezier", points: [0.1, 1, 0, 1], label: "Menu entrance", group: "dotfiles", builtin: true },
        { name: "menu_accel", type: "bezier", points: [0.52, 0.03, 0.72, 0.08], label: "Menu exit", group: "dotfiles", builtin: true },
        { name: "stall", type: "bezier", points: [1, -0.1, 0.7, 0.85], label: "Pause, then go", group: "dotfiles", builtin: true },
        { name: "expressiveSlowSpatial", type: "bezier", points: [0.39, 1.29, 0.35, 0.98], label: "Light bounce", group: "dotfiles", builtin: true },
        { name: "expressiveDefaultSpatial", type: "bezier", points: [0.38, 1.21, 0.22, 1], label: "Medium bounce", group: "dotfiles", builtin: true },
        { name: "expressiveFastSpatial", type: "bezier", points: [0.42, 1.67, 0.21, 0.9], label: "Strong bounce", group: "dotfiles", builtin: true },
        { name: "ii_spring_soft", type: "spring", mass: 1, stiffness: 238.1191, damping: 24.21279333, label: "Soft spring", group: "app", builtin: true },
        { name: "ii_spring_bouncy", type: "spring", mass: 1, stiffness: 260, damping: 18, label: "Bouncy spring", group: "app", builtin: true }
    ]
    readonly property var bezierCurves: root.dotfilesCurves.filter(c => c.type === "bezier")
    readonly property var curveByName: {
        const map = {};
        for (const c of root.dotfilesCurves)
            map[c.name] = c;
        return map;
    }
    // family, kind, percent, direction, speed (deciseconds), curve, enabled
    readonly property var previewCases: [
        ["windowsIn", "popin", 80, "", 3, "emphasizedDecel", true],
        ["windowsIn", "popin", 100, "", 3, "emphasizedDecel", true],
        ["windowsIn", "slide", -1, "", 3, "emphasizedDecel", true],
        ["windowsIn", "slide", -1, "left", 3, "emphasizedDecel", true],
        ["windowsIn", "gnomed", -1, "", 3, "expressiveDefaultSpatial", true],
        ["windowsIn", "popin", 80, "", 3, "ii_spring_bouncy", true],
        ["windowsOut", "popin", 90, "", 2, "emphasizedAccel", true],
        ["windowsMove", "slide", -1, "", 3, "emphasizedDecel", true],
        ["workspaces", "slide", -1, "", 7, "menu_decel", true],
        ["workspaces", "slidevert", -1, "", 7, "menu_decel", true],
        ["workspaces", "fade", -1, "", 7, "menu_decel", true],
        ["workspaces", "slidefade", 50, "", 7, "menu_decel", true],
        ["workspaces", "slidefadevert", 40, "", 7, "menu_decel", true],
        ["specialWorkspaceIn", "slidevert", -1, "", 2.8, "emphasizedDecel", true],
        ["specialWorkspaceOut", "slidevert", -1, "", 1.2, "emphasizedAccel", true],
        ["layersIn", "popin", 93, "", 2.7, "emphasizedDecel", true],
        ["layersOut", "popin", 94, "", 2.4, "menu_accel", true],
        ["border", "none", -1, "", 10, "emphasizedDecel", true],
        ["zoomFactor", "none", -1, "", 3, "standardDecel", true],
        ["windowsIn", "popin", 80, "", 3, "emphasizedDecel", false]
    ]
    readonly property var lightTheme: ({
        background: "#fcf8f8", on_background: "#1c1b1b", surface: "#fcf8f8", surface_dim: "#ddd9d8",
        surface_bright: "#fcf8f8", surface_container_lowest: "#ffffff", surface_container_low: "#f6f2f2",
        surface_container: "#f1edec", surface_container_high: "#ebe7e6", surface_container_highest: "#e5e2e1",
        on_surface: "#1c1b1b", surface_variant: "#e0e2ec", on_surface_variant: "#44474e", inverse_surface: "#313030",
        inverse_on_surface: "#f4f0ef", outline: "#74777f", outline_variant: "#c4c6d0", shadow: "#000000",
        scrim: "#000000", surface_tint: "#415f91", primary: "#415f91", on_primary: "#ffffff",
        primary_container: "#d6e3ff", on_primary_container: "#001b3e", inverse_primary: "#aac7ff",
        secondary: "#565f71", on_secondary: "#ffffff", secondary_container: "#dae2f9",
        on_secondary_container: "#131c2b", tertiary: "#705575", on_tertiary: "#ffffff",
        tertiary_container: "#fad8fd", on_tertiary_container: "#28132e", error: "#ba1a1a", on_error: "#ffffff",
        error_container: "#ffdad6", on_error_container: "#410002"
    })

    property string theme: "dark"
    property int widthCursor: 0
    property int sectionCursor: 0
    property int failures: 0
    property string pickerValue: "emphasizedDecel"
    property string unknownValue: "ii_missing_curve"
    // Curve labels and names come from the user's config: markup in them
    // must be shown literally (a rich-text label would hide the tags).
    readonly property string markupLabel: "<b>Bold</b> <font color='red'>red</font>"
    readonly property string markupValue: "<img src='x'><b>BOLD</b>"
    property var activations: []
    property int editorChanged: 0
    property int editorAccepted: 0

    function report(payload) {
        console.info(`[harness:report] ${JSON.stringify(payload)}`);
    }

    function check(name, ok, detail) {
        root.report({ type: "check", name: name, ok: !!ok, detail: detail ?? "" });
        if (!ok) {
            root.failures++;
            root.report({ type: "fatal", message: `check failed: ${name} ${JSON.stringify(detail ?? "")}` });
        }
    }

    function sectionItem(name) {
        return ({ "thumbs": thumbsSection, "picker": pickerSection, "editor": editorSection,
            "previews-end": previewsSection, "previews-mid": previewsSection })[name];
    }

    // Visible text that is elided or clipped, and items past the window edge.
    function findings(item, acc) {
        if (!item || !item.visible)
            return acc;
        if (item.truncated === true)
            acc.push(`clipped text: ${item.text}`);
        if (item.width > 0) {
            const p = item.mapToItem(gallery, 0, 0);
            if (p.x < -1 || p.x + item.width > win.width + 1)
                acc.push(`past the window edge: ${item.objectName || item.toString()}`);
        }
        // Preview contents are clipped by the mini screen on purpose.
        if (String(item.objectName).startsWith("preview:"))
            return acc;
        for (const child of item.children)
            root.findings(child, acc);
        return acc;
    }

    function startShots() {
        root.widthCursor = 0;
        root.sectionCursor = 0;
        win.width = root.widths[0];
        settleTimer.restart();
    }

    function capture() {
        const name = root.sections[root.sectionCursor];
        const item = root.sectionItem(name);
        for (let i = 0; i < previewRepeater.count; i++) {
            const preview = previewRepeater.itemAt(i)?.preview;
            if (preview)
                preview.seek(name === "previews-mid" ? 0.12 : 1);
        }
        win.height = Math.max(200, Math.ceil(gallery.implicitHeight));
        Qt.callLater(() => {
            const size = `${win.width}x${win.height}`;
            const file = `${root.outDir}/${root.widths[root.widthCursor]}-${root.theme}-${name}.png`;
            const problems = root.findings(item, []);
            const started = item.grabToImage(result => {
                const saved = result.saveToFile(file);
                root.report({ type: "page", size: size, name: `${root.theme}/${name}`, file: file, saved: saved,
                    rows: 0, overlaps: [], overflowX: problems, openPopups: 0 });
                root.advance();
            });
            if (!started) {
                root.report({ type: "fatal", message: `grabToImage refused for ${name}` });
                quitTimer.start();
            }
        });
    }

    function advance() {
        if (root.sectionCursor + 1 < root.sections.length) {
            root.sectionCursor++;
            settleTimer.restart();
            return;
        }
        if (root.widthCursor + 1 < root.widths.length) {
            root.widthCursor++;
            root.sectionCursor = 0;
            win.width = root.widths[root.widthCursor];
            settleTimer.restart();
            return;
        }
        if (root.theme === "dark") {
            root.theme = "light";
            MaterialThemeLoader.applyColors(JSON.stringify(root.lightTheme));
            root.startShots();
            return;
        }
        root.interactions();
    }

    // ---------------------------------------------------------- interactions

    function interactions() {
        win.width = 1100;
        win.requestActivate();
        Qt.callLater(root.checkPicker);
    }

    function checkPicker() {
        const curves = root.dotfilesCurves;
        const start = curves.findIndex(c => c.name === "emphasizedDecel");
        root.pickerValue = "emphasizedDecel";
        root.activations = [];
        beforePicker.forceActiveFocus();
        events.keyClick(Qt.Key_Tab, Qt.NoModifier, -1);
        root.check("picker: Tab enters the group on the selected curve", picker.activeFocus && picker.focusIndex === start,
            { activeFocus: picker.activeFocus, focusIndex: picker.focusIndex, expected: start });
        root.check("picker: Tab shows the focus ring", picker.keyboardFocus, {});
        events.keyClick(Qt.Key_Right, Qt.NoModifier, -1);
        root.check("picker: Right moves focus without choosing", picker.focusIndex === start + 1 && root.activations.length === 0,
            { focusIndex: picker.focusIndex, activations: root.activations });
        events.keyClick(Qt.Key_Left, Qt.NoModifier, -1);
        events.keyClick(Qt.Key_Left, Qt.NoModifier, -1);
        root.check("picker: Left moves back", picker.focusIndex === start - 1, { focusIndex: picker.focusIndex });
        events.keyClick(Qt.Key_End, Qt.NoModifier, -1);
        root.check("picker: End goes to the last curve", picker.focusIndex === curves.length - 1, { focusIndex: picker.focusIndex });
        events.keyClick(Qt.Key_Down, Qt.NoModifier, -1);
        root.check("picker: Down stops at the last curve", picker.focusIndex === curves.length - 1, { focusIndex: picker.focusIndex });
        events.keyClick(Qt.Key_Space, Qt.NoModifier, -1);
        root.check("picker: Space chooses the focused curve", root.pickerValue === curves[curves.length - 1].name,
            { value: root.pickerValue, activations: root.activations });
        events.keyClick(Qt.Key_Home, Qt.NoModifier, -1);
        root.check("picker: Home goes to the first curve", picker.focusIndex === 0, { focusIndex: picker.focusIndex });
        events.keyClick(Qt.Key_Return, Qt.NoModifier, -1);
        root.check("picker: Enter chooses the focused curve", root.pickerValue === curves[0].name && root.activations.length === 2,
            { value: root.pickerValue, activations: root.activations });
        events.keyClick(Qt.Key_Tab, Qt.NoModifier, -1);
        root.check("picker: Tab leaves the group", !picker.activeFocus && afterPicker.activeFocus,
            { picker: picker.activeFocus, after: afterPicker.activeFocus });
        events.keyClick(Qt.Key_Tab, Qt.ShiftModifier, -1);
        root.check("picker: Shift+Tab comes back to the chosen curve", picker.activeFocus && picker.focusIndex === 0,
            { activeFocus: picker.activeFocus, focusIndex: picker.focusIndex });

        // Unknown value: an extra item stands for it and keeps it.
        unknownPicker.forceActiveFocus();
        const extra = unknownPicker.items.length - 1;
        root.check("picker: an unknown curve gets its own item", unknownPicker.unrecognized && unknownPicker.items[extra].name === root.unknownValue
            && unknownPicker.selectedIndex === extra, { items: unknownPicker.items.length, selected: unknownPicker.selectedIndex });
        root.check("picker: the unknown item has the focus", unknownPicker.focusIndex === extra, { focusIndex: unknownPicker.focusIndex });
        events.keyClick(Qt.Key_Space, Qt.NoModifier, -1);
        root.check("picker: choosing the unknown item keeps the value", root.unknownValue === "ii_missing_curve", { value: root.unknownValue });
        root.check("picker: the unknown item is labelled", unknownPicker.labelFor(unknownPicker.items[extra]).indexOf("ii_missing_curve") >= 0,
            { label: unknownPicker.labelFor(unknownPicker.items[extra]) });
        const userLabel = root.findByName(markupPicker, "curveLabel:user_markup");
        root.check("picker: a user label with markup is shown as plain text", userLabel && userLabel.textFormat === Text.PlainText
            && userLabel.text === root.markupLabel, { textFormat: userLabel?.textFormat, text: userLabel?.text });
        const unknownLabel = root.findByName(markupPicker, "curveLabel:" + root.markupValue);
        root.check("picker: an unknown name with markup is shown as plain text", unknownLabel && unknownLabel.textFormat === Text.PlainText
            && unknownLabel.text.indexOf(root.markupValue) >= 0, { textFormat: unknownLabel?.textFormat, text: unknownLabel?.text });
        root.checkEditor();
    }

    function same(a, b) {
        return a.length === b.length && a.every((v, i) => Math.abs(v - b[i]) < 1e-9);
    }

    function drag(item, dx, dy) {
        const cx = item.width / 2;
        const cy = item.height / 2;
        events.mousePress(item, cx, cy, Qt.LeftButton, Qt.NoModifier, -1);
        for (let i = 1; i <= 4; i++)
            events.mouseMove(item, cx + dx * i / 4, cy + dy * i / 4, -1, Qt.LeftButton, Qt.NoModifier);
        events.mouseRelease(item, cx + dx, cy + dy, Qt.LeftButton, Qt.NoModifier, -1);
    }

    function findByName(item, name) {
        if (!item)
            return null;
        if (item.objectName === name)
            return item;
        for (const child of item.children) {
            const hit = root.findByName(child, name);
            if (hit)
                return hit;
        }
        return null;
    }

    function typeText(text) {
        for (const ch of text)
            events.keyClickChar(ch, Qt.NoModifier, -1);
    }

    function checkEditor() {
        editor.points = [0.05, 0.7, 0.1, 1];
        root.editorChanged = 0;
        root.editorAccepted = 0;
        const first = root.findByName(editor, "curveHandle:0");
        const second = root.findByName(editor, "curveHandle:1");
        root.drag(first, -2000, -2000);
        root.check("editor: dragging past the top-left clamps the first point to x 0, y 2", root.same(editor.points.slice(0, 2), [0, 2]),
            { points: editor.points });
        root.check("editor: a drag emits changed and one accepted", root.editorChanged > 0 && root.editorAccepted === 1,
            { changed: root.editorChanged, accepted: root.editorAccepted });
        root.drag(second, 2000, 2000);
        root.check("editor: dragging past the bottom-right clamps the second point to x 1, y -1", root.same(editor.points.slice(2), [1, -1]),
            { points: editor.points });

        editor.points = [0.05, 0.7, 0.1, 1];
        const x1 = root.findByName(editor, "curveField:0");
        const y2 = root.findByName(editor, "curveField:3");
        const start = [0.05, 0.7, 0.1, 1];
        // Each step acts, and the next one checks after the window has
        // delivered the events.
        root.runSteps([
            () => {
                x1.forceActiveFocus();
                events.keyClick(Qt.Key_A, Qt.ControlModifier, -1);
                root.typeText("1.5");
            },
            () => {
                root.check("editor: x out of [0, 1] is invalid and not applied", x1.invalid && editor.invalidMessage.length > 0
                    && editor.points[0] <= 1, { invalid: x1.invalid, message: editor.invalidMessage, points: editor.points });
                events.keyClick(Qt.Key_A, Qt.ControlModifier, -1);
                root.typeText("0.4");
                events.keyClick(Qt.Key_Return, Qt.NoModifier, -1);
            },
            () => {
                root.check("editor: a valid x is applied", root.same(editor.points, [0.4, 0.7, 0.1, 1]) && !x1.invalid
                    && editor.invalidMessage === "" && x1.text === "0.40", { points: editor.points, text: x1.text, message: editor.invalidMessage });
                events.keyClick(Qt.Key_Up, Qt.NoModifier, -1);
            },
            () => {
                root.check("editor: Up steps 0.01", root.same(editor.points, [0.41, 0.7, 0.1, 1]) && x1.text === "0.41", { points: editor.points, text: x1.text });
                events.keyClick(Qt.Key_Up, Qt.ShiftModifier, -1);
            },
            () => {
                root.check("editor: Shift+Up steps 0.1", root.same(editor.points, [0.51, 0.7, 0.1, 1]), { points: editor.points });
                for (let i = 0; i < 6; i++)
                    events.keyClick(Qt.Key_Up, Qt.ShiftModifier, -1);
            },
            () => {
                root.check("editor: steps stop at x 1", root.same(editor.points, [1, 0.7, 0.1, 1]), { points: editor.points });
                events.keyClick(Qt.Key_Down, Qt.NoModifier, -1);
            },
            () => {
                root.check("editor: Down steps -0.01", root.same(editor.points, [0.99, 0.7, 0.1, 1]), { points: editor.points });
                y2.forceActiveFocus();
                events.keyClick(Qt.Key_A, Qt.ControlModifier, -1);
                root.typeText("-3");
            },
            () => {
                root.check("editor: y out of [-1, 2] is invalid", y2.invalid && editor.invalidMessage.length > 0, { message: editor.invalidMessage });
                x1.forceActiveFocus();
            },
            () => {
                root.check("editor: leaving an invalid field restores its value", !y2.invalid && y2.text === "1.00" && editor.invalidMessage === ""
                    && root.same(editor.points, [0.99, 0.7, 0.1, 1]), { text: y2.text, message: editor.invalidMessage, points: editor.points });
                events.keyClick(Qt.Key_A, Qt.ControlModifier, -1);
                root.typeText("abc");
            },
            () => {
                root.check("editor: text that is not a number is invalid", x1.invalid, { text: x1.text });
                events.keyClick(Qt.Key_Return, Qt.NoModifier, -1);
            },
            () => {
                root.check("editor: Enter on an invalid field restores it", x1.text === "0.99" && root.same(editor.points, [0.99, 0.7, 0.1, 1]),
                    { text: x1.text, points: editor.points });
                editor.setPoints([-1, 5, 3, -7], true);
                root.check("editor: setPoints clamps", root.same(editor.points, [0, 2, 1, -1]), { points: editor.points });
                root.checkStartFrom();
            }
        ]);
    }

    // "Start from…" lists the base curves by label: a user label with markup
    // must show literally in the popup, as in the picker.
    function checkStartFrom() {
        const startFrom = root.findByName(editor, "curveStartFrom");
        const markupCurve = { name: "user_markup", type: "bezier", points: [0.2, 0.4, 0.6, 0.8], label: root.markupLabel, group: "user" };
        editor.baseCurves = root.bezierCurves.slice(0, 1).concat([markupCurve]);
        root.runSteps([
            () => startFrom.popup.open(),
            () => {
                const label = root.findByName(startFrom.popup.contentItem, "curveStartFromLabel:1");
                root.check("editor: a user label with markup is shown as plain text in Start from", label && label.textFormat === Text.PlainText
                    && label.text === root.markupLabel, { textFormat: label?.textFormat, text: label?.text });
                startFrom.popup.close();
                editor.baseCurves = Qt.binding(() => root.bezierCurves);
                beforePicker.forceActiveFocus();
                root.checkPreview();
            }
        ]);
    }

    property var pendingSteps: []

    function runSteps(steps) {
        root.pendingSteps = steps;
        stepTimer.restart();
    }

    Timer {
        id: stepTimer
        interval: 60
        onTriggered: {
            const steps = root.pendingSteps;
            const next = steps.shift();
            root.pendingSteps = steps;
            next();
            if (root.pendingSteps.length > 0)
                stepTimer.restart();
        }
    }

    property double playStarted: 0

    function near(a, b, tolerance) {
        return typeof a === "number" && typeof b === "number" && Math.abs(a - b) <= tolerance;
    }

    // Fixed frames of the gallery previews: the progress goes through
    // CurveMath, and each family's geometry follows the mapped value.
    function checkPreviewFrames() {
        const previewAt = index => previewRepeater.itemAt(index).preview;
        const caseOf = index => root.previewCases[index];
        // popin 80, slide left, windowsOut popin 90, a spring, workspaces slidefade 50%.
        for (const index of [0, 3, 5, 6, 11]) {
            const preview = previewAt(index);
            const curve = root.curveByName[caseOf(index)[5]];
            preview.seek(0.3);
            const expected = CurveMath.valueAt(curve, 0.3, preview.effectiveDurationMs);
            root.check(`preview: ${caseOf(index).slice(0, 4).join(" ")} ${curve.name} maps progress through CurveMath`,
                root.near(preview.value, expected, 1e-9), { value: preview.value, expected: expected });
        }
        const decel = previewAt(3);
        decel.seek(0.3);
        root.check("preview: a decelerating curve is not linear", Math.abs(decel.value - 0.3) > 0.1, { value: decel.value });

        // windowsIn slide left: the window comes in from the left edge.
        const slide = previewAt(3);
        const sw = slide.width;
        const gw = sw * 0.46;
        const gx = (sw - gw) / 2;
        const slideWindow = root.findByName(slide, "previewWindow");
        slide.seek(0.1);
        root.check("preview: slide left starts left of its place and follows the value",
            slideWindow.x < gx && root.near(slideWindow.x, gx - gw * (1 - slide.value), 0.5),
            { x: slideWindow.x, rest: gx, value: slide.value });
        slide.seek(1);
        root.check("preview: slide left ends in place", root.near(slideWindow.x, gx, 0.5), { x: slideWindow.x, rest: gx });

        // windowsIn slide with no direction: the nearest edge is the bottom.
        const nearest = previewAt(2);
        const nearestWindow = root.findByName(nearest, "previewWindow");
        nearest.seek(0);
        root.check("preview: slide with no direction comes from the nearest edge (bottom)",
            root.near(nearestWindow.y, nearest.height, 0.5) && root.near(nearestWindow.x, gx, 0.5),
            { x: nearestWindow.x, y: nearestWindow.y, height: nearest.height });

        // windowsIn popin 80%: starts at 80 % of the size, transparent.
        const popin = previewAt(0);
        const popinWindow = root.findByName(popin, "previewWindow");
        popin.seek(0);
        root.check("preview: popin 80% starts at 80% of the size, transparent",
            root.near(popinWindow.width, gw * 0.8, 0.5) && popinWindow.opacity === 0, { width: popinWindow.width, opacity: popinWindow.opacity });

        // windowsOut: opaque at the first frame, gone at the last.
        const closing = previewAt(6);
        const closingWindow = root.findByName(closing, "previewWindow");
        closing.seek(0);
        const startOpacity = closingWindow.opacity;
        const startWidth = closingWindow.width;
        closing.seek(1);
        root.check("preview: windowsOut goes from opaque and full size to transparent at 90%",
            startOpacity === 1 && root.near(startWidth, gw, 0.5) && closingWindow.opacity === 0 && root.near(closingWindow.width, gw * 0.9, 0.5),
            { startOpacity: startOpacity, startWidth: startWidth, endOpacity: closingWindow.opacity, endWidth: closingWindow.width });

        // workspaces slidefade 50%: the incoming workspace moves half the
        // screen and fades in; the current one moves away and fades out.
        const ws = previewAt(11);
        const incoming = root.findByName(ws, "previewIncomingWorkspace");
        const current = root.findByName(ws, "previewCurrentWorkspace");
        ws.seek(0.3);
        const v = ws.value;
        root.check("preview: workspaces slidefade 50% offsets the incoming workspace by half the screen",
            root.near(incoming.transform[0].x, 0.5 * ws.width * (1 - v), 0.5) && root.near(current.transform[0].x, -0.5 * ws.width * v, 0.5)
            && root.near(incoming.opacity, v, 1e-6) && root.near(current.opacity, 1 - v, 1e-6),
            { incomingX: incoming.transform[0].x, currentX: current.transform[0].x, value: v, width: ws.width });
        for (let i = 0; i < previewRepeater.count; i++)
            previewAt(i).seek(1);
    }

    function checkPreview() {
        root.checkPreviewFrames();
        const preview = playTarget;
        preview.reduceMotion = true;
        preview.seek(0);
        preview.play(true);
        root.check("preview: no automatic replay with reduceMotion", !preview.playing && preview.progress === 1, { progress: preview.progress });
        preview.reduceMotion = false;
        disabledTarget.seek(0);
        disabledTarget.play();
        root.check("preview: a disabled animation jumps to the end", !disabledTarget.playing && disabledTarget.progress === 1, {});
        root.check("preview: a spring lasts until Hyprland ends it", springTarget.effectiveDurationMs === CurveMath.springSettleMs(root.curveByName.ii_spring_bouncy),
            { duration: springTarget.effectiveDurationMs });
        root.check("preview: a bezier lasts speed * 100 ms", preview.effectiveDurationMs === 300, { duration: preview.effectiveDurationMs });
        root.playStarted = Date.now();
        preview.play();
        root.check("preview: play() starts at the first frame", preview.playing && preview.progress < 0.5, { progress: preview.progress });
        playWatch.restart();
    }

    function finishPreview() {
        const preview = playTarget;
        const elapsed = Date.now() - root.playStarted;
        root.check("preview: played to its end once", !preview.playing && preview.progress === 1 && Math.abs(preview.value - 1) < 1e-9,
            { progress: preview.progress, value: preview.value });
        root.check("preview: took about the animation's duration", elapsed >= 250, { elapsed: elapsed });
        root.report({ type: "done", failures: root.failures });
        quitTimer.start();
    }

    TestEvent {
        id: events
    }

    Timer {
        id: playWatch
        property int waited: 0
        interval: 50
        repeat: true
        onTriggered: {
            waited += interval;
            if (playTarget.playing && waited < 5000)
                return;
            stop();
            // A finished animation must stay at the end: wait a little more.
            endWait.start();
        }
    }

    Timer {
        id: endWait
        interval: 400
        onTriggered: root.finishPreview()
    }

    Window {
        id: win
        visible: true
        width: 1100 // size-ok: harness window
        height: 900 // size-ok: harness window
        color: Appearance.colors.colLayer0Base

        Rectangle {
            id: gallery
            anchors.left: parent.left
            anchors.right: parent.right
            implicitHeight: column.implicitHeight + 48
            color: Appearance.colors.colLayer0Base

            ColumnLayout {
                id: column
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 24
                spacing: 24

                GallerySection {
                    id: thumbsSection
                    title: "SettingsCurveThumb"

                    Flow {
                        Layout.fillWidth: true
                        spacing: 10

                        Repeater {
                            model: root.dotfilesCurves

                            delegate: ColumnLayout {
                                id: thumbCell
                                required property var modelData
                                required property int index
                                spacing: 4

                                SettingsCurveThumb {
                                    curve: thumbCell.modelData
                                    selected: thumbCell.index === 2
                                    forceHovered: thumbCell.index === 3
                                    focusShown: thumbCell.index === 4
                                    enabled: thumbCell.index !== 5
                                }

                                StyledText {
                                    text: thumbCell.modelData.name
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: Appearance.colors.colSubtext
                                }
                            }
                        }

                        ColumnLayout {
                            spacing: 4

                            SettingsCurveThumb {
                                curve: null
                            }

                            StyledText {
                                text: "unknown"
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                color: Appearance.colors.colSubtext
                            }
                        }
                    }
                }

                GallerySection {
                    id: pickerSection
                    title: "SettingsCurvePicker"

                    SettingsButton {
                        id: beforePicker
                        text: "Before"
                    }

                    SettingsCurvePicker {
                        id: picker
                        Layout.fillWidth: true
                        curves: root.dotfilesCurves
                        value: root.pickerValue
                        accessibleName: "Curve"
                        onActivated: name => {
                            root.activations = root.activations.concat([name]);
                            root.pickerValue = name;
                        }
                    }

                    SettingsButton {
                        id: afterPicker
                        text: "After"
                    }

                    SettingsCurvePicker {
                        id: unknownPicker
                        Layout.fillWidth: true
                        curves: root.dotfilesCurves.slice(0, 4)
                        value: root.unknownValue
                        accessibleName: "Curve"
                        onActivated: name => root.unknownValue = name
                    }
                }

                GallerySection {
                    id: editorSection
                    title: "SettingsCurveEditor"

                    SettingsCurveEditor {
                        id: editor
                        Layout.fillWidth: true
                        // Differs from the original so both curves show.
                        points: [0.3, 1.4, 0.2, 0.95]
                        originalPoints: [0.05, 0.7, 0.1, 1]
                        baseCurves: root.bezierCurves
                        durationMs: 300
                        onChanged: root.editorChanged++
                        onAccepted: root.editorAccepted++
                    }

                    // Narrow: the plot and the fields stack.
                    SettingsCurveEditor {
                        Layout.fillWidth: true
                        Layout.maximumWidth: 420
                        points: [1, -0.1, 0.7, 0.85]
                        originalPoints: [0.42, 1.67, 0.21, 0.9]
                        baseCurves: root.bezierCurves
                    }
                }

                GallerySection {
                    id: previewsSection
                    title: "SettingsAnimationPreview"

                    Flow {
                        Layout.fillWidth: true
                        spacing: 12

                        Repeater {
                            id: previewRepeater
                            model: root.previewCases

                            delegate: ColumnLayout {
                                id: previewCell
                                required property var modelData
                                required property int index
                                property alias preview: previewItem
                                spacing: 4

                                SettingsAnimationPreview {
                                    id: previewItem
                                    objectName: "preview:" + previewCell.index
                                    Layout.preferredWidth: 220
                                    family: previewCell.modelData[0]
                                    kind: previewCell.modelData[1]
                                    percent: previewCell.modelData[2]
                                    direction: previewCell.modelData[3]
                                    durationMs: CurveMath.speedToMs(previewCell.modelData[4])
                                    curve: root.curveByName[previewCell.modelData[5]]
                                    enabled: previewCell.modelData[6]
                                    startAtEnd: true
                                }

                                StyledText {
                                    Layout.preferredWidth: 220
                                    text: `${previewCell.modelData[0]} · ${previewCell.modelData[1]}${previewCell.modelData[2] >= 0 ? " " + previewCell.modelData[2] + "%" : ""}${previewCell.modelData[3] ? " " + previewCell.modelData[3] : ""}`
                                    elide: Text.ElideRight
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: Appearance.colors.colSubtext
                                }
                            }
                        }
                    }
                }

                // Interaction targets, outside the screenshots.
                RowLayout {
                    spacing: 12

                    SettingsAnimationPreview {
                        id: playTarget
                        Layout.preferredWidth: 160
                        family: "windowsIn"
                        kind: "popin"
                        percent: 80
                        durationMs: 300
                        curve: root.curveByName.emphasizedDecel
                    }

                    SettingsAnimationPreview {
                        id: disabledTarget
                        Layout.preferredWidth: 160
                        enabled: false
                    }

                    SettingsAnimationPreview {
                        id: springTarget
                        Layout.preferredWidth: 160
                        curve: root.curveByName.ii_spring_bouncy
                    }
                }

                SettingsCurvePicker {
                    id: markupPicker
                    Layout.preferredWidth: 240
                    curves: [{ name: "user_markup", type: "bezier", points: CurveMath.DEFAULT_POINTS, label: root.markupLabel, group: "user" }]
                    value: root.markupValue
                    accessibleName: "Curve"
                }
            }
        }
    }

    // An opaque backdrop (like the settings window) around a layer-1 card:
    // the layer colours are translucent, and a screenshot of the card alone
    // would show them over nothing.
    component GallerySection: Rectangle {
        id: section
        property string title: ""
        default property alias content: sectionColumn.data
        readonly property color backdrop: Appearance.m3colors.m3background

        Layout.fillWidth: true
        implicitHeight: card.implicitHeight
        color: Qt.rgba(section.backdrop.r, section.backdrop.g, section.backdrop.b, 1)

        Rectangle {
            id: card
            anchors.fill: parent
            implicitHeight: sectionColumn.implicitHeight + 32
            radius: SettingsMetrics.cardRadius
            color: Appearance.colors.colLayer1

            ColumnLayout {
                id: sectionColumn
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 16
                spacing: 12

                StyledText {
                    text: section.title
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.Medium
                    color: Appearance.colors.colOnLayer1
                }
            }
        }
    }

    Timer {
        id: settleTimer
        interval: 500
        onTriggered: root.capture()
    }

    Timer {
        id: quitTimer
        interval: 200
        onTriggered: Qt.quit()
    }

    // Waits for the config (fonts, language) and the translations.
    Timer {
        id: bootTimer
        property int waited: 0
        interval: 100
        repeat: true
        running: true
        onTriggered: {
            waited += interval;
            if (!Config.ready || Translation.isLoading || Object.keys(Translation.translations).length === 0) {
                if (waited > 20000) {
                    stop();
                    root.report({ type: "fatal", message: "config or translations never loaded" });
                    quitTimer.start();
                }
                return;
            }
            stop();
            MaterialThemeLoader.reapplyTheme();
            startDelay.start();
        }
    }

    Timer {
        id: startDelay
        interval: 1200
        onTriggered: {
            root.report({ type: "start", widths: root.widths, sections: root.sections });
            root.startShots();
        }
    }
}
