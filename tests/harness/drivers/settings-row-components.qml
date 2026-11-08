//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
//@ pragma Env QT_SCALE_FACTOR=1

// Harness driver (run.sh --hyprland-stub --driver): layout and texts of the
// shared row components (SettingsSelectRow, SettingsChip, SettingsRow's label
// line, SettingsSliderRow, SettingsWindowPreview). tests/test_settings_row_components.py
// reads the reports.
//
// Steps:
// - quick-select: the Quick page is the first page, created while the
//   translations load; its select rows (power mode is a device row) show the
//   option the row says is selected, also after the options are rebuilt.
// - requires-chip: at 760 px a "Requires «…»" chip wraps instead of eliding
//   the name of the setting it depends on.
// - modified-dot: a wrapped, modified label keeps the dot right after the end
//   of its last line.
// - decimals: a slider's value uses the locale's decimal separator, like the
//   preview's magnifier.
// - preview-a11y: the two previews of the Windows page have their own
//   accessible names, and the effects preview describes the effects.
import QtQuick
import Quickshell
import QtTest
import qs.modules.common
// @harness-imports

ShellRoot {
    id: root

    property var win: null
    property int failures: 0
    property var steps: []
    property int stepIndex: 0

    function report(payload) {
        console.info(`[harness:report] ${JSON.stringify(payload)}`);
    }

    function check(name, ok, detail) {
        root.report(Object.assign({ type: "check", name: name, ok: !!ok }, detail ?? {}));
        if (!ok)
            root.failures++;
        return !!ok;
    }

    function finish() {
        root.report({ type: "done", failures: root.failures });
        quitTimer.start();
    }

    function fatal(message) {
        root.failures++;
        root.report({ type: "fatal", message: message });
        root.finish();
    }

    function next() {
        if (root.stepIndex >= root.steps.length)
            return root.finish();
        const step = root.steps[root.stepIndex++];
        step();
    }

    function walk(item, visit) {
        if (!item)
            return;
        visit(item);
        for (const child of item.children)
            root.walk(child, visit);
    }

    function find(item, name) {
        let found = null;
        root.walk(item, i => {
            if (!found && i.objectName === name)
                found = i;
        });
        return found;
    }

    function findAll(item, prefix) {
        const acc = [];
        root.walk(item, i => {
            if (String(i.objectName ?? "").startsWith(prefix))
                acc.push(i);
        });
        return acc;
    }

    function currentPageId() {
        return root.win.pages[root.win.currentPage]?.id ?? "";
    }

    function openPage(pageId, done) {
        root.win.openPage(pageId);
        root.waitFor(() => root.win.pageReady && root.currentPageId() === pageId, 6000, done);
    }

    // The row of `key` rendered by page `pageId` (aliases share the objectName).
    function rowOn(pageId, key) {
        return root.findAll(root.win.contentItem, "row:" + key).find(r => r.objectName === "row:" + key && r.page?.pageId === pageId) ?? null;
    }

    function waitFor(test, timeoutMs, done) {
        pollComponent.createObject(root, { deadline: Date.now() + timeoutMs, test: test, done: done }).start();
    }

    function later(ms, action) {
        laterComponent.createObject(root, { interval: ms, action: action }).start();
    }

    function saveShot(item, name, then) {
        const dir = Quickshell.env("SHOT_DIR");
        const started = !!dir && !!item && item.grabToImage(result => {
            result.saveToFile(`${dir}/${name}.png`);
            root.report({ type: "image", name: name, file: `${dir}/${name}.png` });
            then();
        });
        if (!started)
            then();
    }

    // The combo box of a select row (the StyledComboBox in its control box).
    function comboOf(row) {
        let combo = null;
        root.walk(row, i => {
            if (!combo && i.popup !== undefined && i.textRole !== undefined && i.currentIndex !== undefined)
                combo = i;
        });
        return combo;
    }

    function selectState(row) {
        const combo = root.comboOf(row);
        return {
            key: row?.settingKey ?? null,
            value: row?.value ?? null,
            rowIndex: row?.currentIndex ?? null,
            comboIndex: combo?.currentIndex ?? null,
            shown: combo?.displayText ?? null,
            expected: row && row.currentIndex >= 0 ? row.options[row.currentIndex].label : null
        };
    }

    function selectMatches(state) {
        return state.rowIndex >= 0 && state.comboIndex === state.rowIndex && state.shown === state.expected;
    }

    // ------------------------------------------------------------ quick-select

    function quickSelectStep() {
        const quick = "quick";
        root.waitFor(() => root.currentPageId() === quick && root.rowOn(quick, "power.profile")?.currentIndex >= 0, 8000, ready => {
            const power = root.rowOn(quick, "power.profile");
            const state = root.selectState(power);
            root.check("quick-select: power mode shows the selected option", ready && root.selectMatches(state), state);
            // Every select row of the page, whatever its options' origin.
            const rows = root.findAll(root.win.contentItem, "row:").filter(r => r.page?.pageId === quick && r.options !== undefined && r.currentIndex >= 0 && root.comboOf(r) !== null);
            const wrong = rows.map(r => root.selectState(r)).filter(s => !root.selectMatches(s));
            root.check("quick-select: every select row shows its selected option", rows.length > 0 && wrong.length === 0, { rows: rows.length, wrong: wrong });
            // Rebuilding the options (new labels, same values) keeps the selection.
            const before = power.rawOptions;
            power.rawOptions = before.map(o => Object.assign({}, o, { label: `${o.label ?? o.value} (test)`, translate: false }));
            root.later(100, () => {
                const rebuilt = root.selectState(power);
                root.check("quick-select: rebuilt options keep the selected option", root.selectMatches(rebuilt), rebuilt);
                power.rawOptions = before;
                root.later(100, () => root.saveShot(power, "quick-power", () => root.next()));
            });
        });
    }

    // ------------------------------------------------------- narrow-window steps

    readonly property var narrowPages: ["windows", "input", "appearance"]
    property var wrappedDecorated: []

    function narrowStep() {
        root.win.width = 760;
        root.win.height = 720;
        const run = index => {
            if (index >= root.narrowPages.length) {
                root.check("modified-dot: wrapped labels with decorations found", root.wrappedDecorated.length > 0
                    && root.wrappedDecorated.some(r => r.modified), { rows: root.wrappedDecorated });
                return root.next();
            }
            const pageId = root.narrowPages[index];
            root.openPage(pageId, ready => {
                root.later(400, () => {
                    root.check(`narrow: ${pageId} opened at 760 px`, ready && root.win.width === 760, { page: root.currentPageId() });
                    root.chipsOn(pageId);
                    root.decorationsOn(pageId);
                    run(index + 1);
                });
            });
        };
        run(0);
    }

    function textOf(chip) {
        let text = null;
        root.walk(chip, i => {
            if (!text && i.truncated !== undefined && i.text === chip.label)
                text = i;
        });
        return text;
    }

    function labelLineOf(item) {
        let p = item.parent;
        while (p && !(p.flow !== undefined && p.spacing !== undefined))
            p = p.parent;
        return p;
    }

    // Every "Requires «…»" chip of the page shows its whole text (at most two
    // lines) inside the label line.
    function chipsOn(pageId) {
        const rows = root.findAll(root.win.contentItem, "row:").filter(r => r.page?.pageId === pageId && r.requires);
        const states = rows.map(r => {
            const chip = root.find(r, "chip:requires");
            const text = chip ? root.textOf(chip) : null;
            const line = chip ? root.labelLineOf(chip) : null;
            const bottom = chip && line ? chip.mapToItem(line, 0, chip.height).y : -1;
            return {
                key: r.settingKey, label: chip?.label ?? null, truncated: text?.truncated ?? null, lines: text?.lineCount ?? null,
                chipWidth: chip?.width ?? null, lineWidth: line?.width ?? null, chipBottom: bottom, lineHeight: line?.height ?? null
            };
        });
        const bad = states.filter(s => s.truncated !== false || s.lines > 2 || s.chipWidth > s.lineWidth + 0.5 || s.chipBottom > s.lineHeight + 0.5);
        root.check(`requires-chip: ${pageId}: the chip shows the whole name at 760 px`, states.length > 0 && bad.length === 0, { chips: states, bad: bad });
        root.report({ type: "chips", page: pageId, chips: states });
    }

    // A wrapped label keeps the modified dot and the "?" right after the end
    // of its last line, on that line.
    function decorationsOn(pageId) {
        const rows = root.findAll(root.win.contentItem, "row:").filter(r => r.page?.pageId === pageId && r.visible);
        const bad = [];
        for (const r of rows) {
            const deco = root.find(r, "labelDecorations");
            const label = deco?.parent?.children?.[0] ?? null;
            if (!deco || !label || label.lineCount === undefined || label.lineCount < 2 || deco.width <= 0)
                continue;
            const firstLineBottom = label.topPadding + label.contentHeight / label.lineCount;
            const centerY = deco.y + deco.height / 2;
            const gap = deco.x - label.lastLineEnd;
            const state = { key: r.settingKey, modified: r.modified, lines: label.lineCount, gap: gap, centerY: centerY,
                firstLineBottom: firstLineBottom, lastLineEnd: label.lastLineEnd, labelWidth: label.width, decoRight: deco.x + deco.width,
                boxWidth: deco.parent.width };
            root.wrappedDecorated.push(state);
            if (!(gap >= 0 && gap <= 12 && centerY > firstLineBottom && label.lastLineEnd < label.width && state.decoRight <= state.boxWidth + 0.5))
                bad.push(state);
        }
        root.check(`modified-dot: ${pageId}: decorations follow the last line of a wrapped label`, bad.length === 0, { bad: bad });
    }

    // ---------------------------------------------------------------- decimals

    function decimalsStep() {
        root.openPage("windows", ready => {
            const row = root.rowOn("windows", "hyprland.decoration.rounding_power");
            const value = row ? root.find(row, "sliderValue") : null;
            const lens = root.find(root.win.contentItem, "magnifierLabel:rounding");
            const locale = Qt.locale();
            const number = value ? value.text.replace(row.unit, "") : "";
            root.check("decimals: the slider uses the locale's decimal separator", ready && !!value && row.decimals > 0
                && number.indexOf(locale.decimalPoint) >= 0 && number === Number(row.value).toLocaleString(locale, "f", row.decimals), {
                text: value?.text ?? null, decimalPoint: locale.decimalPoint, decimals: row?.decimals ?? null });
            root.check("decimals: the slider and the magnifier show the same number", !!lens && number.length > 0 && lens.text.indexOf(number) >= 0, {
                slider: number, magnifier: lens?.text ?? null });
            const plain = "6500" + (row && row.decimals > 0 ? locale.decimalPoint + "0".repeat(row.decimals) : "") + (row?.unit ?? "");
            root.check("decimals: no group separator", !!row && row.format(6500) === plain, { formatted: row?.format(6500) ?? null, expected: plain });
            root.next();
        });
    }

    // ------------------------------------------------------------ preview-a11y

    function previewA11yStep() {
        const canvases = root.findAll(root.win.contentItem, "windowPreviewDesktop");
        const effects = root.find(root.win.contentItem, "windowEffectsPreview");
        const effectsCanvas = effects ? root.find(effects, "windowPreviewDesktop") : null;
        const layoutCanvas = canvases.find(c => c !== effectsCanvas) ?? null;
        const names = canvases.map(c => c.Accessible.name);
        root.check("preview-a11y: two previews with different accessible names", canvases.length === 2 && names[0] !== names[1]
            && layoutCanvas?.Accessible.name === Translation.tr("Preview") && effectsCanvas?.Accessible.name === Translation.tr("Effects preview"), { names: names });
        const description = effectsCanvas?.Accessible.description ?? "";
        const v = effects?.model?.values ?? {};
        const parts = [
            v.blur ? Translation.tr("Blur behind the bar and panels: %1 px, %2 passes").arg(Math.round(v.blurSize)).arg(v.blurPasses) : Translation.tr("No blur behind the bar and panels"),
            v.shadow ? Translation.tr("Shadow of floating windows: %1 px").arg(Math.round(v.shadowRange)) : Translation.tr("No shadow on floating windows"),
            Translation.tr("Opacity: %1 % for the active window, %2 % for the others").arg(Math.round(v.activeOpacity * 100)).arg(Math.round(v.inactiveOpacity * 100)),
            v.dim ? Translation.tr("Inactive windows dimmed by %1 %").arg(Math.round(v.dimStrength * 100)) : Translation.tr("Inactive windows are not dimmed")
        ];
        root.check("preview-a11y: the effects preview describes blur, shadow, opacity and dimming", !!effectsCanvas && parts.every(p => description.indexOf(p) >= 0)
            && description !== layoutCanvas?.Accessible.description, { description: description, layout: layoutCanvas?.Accessible.description ?? null });
        root.check("preview-a11y: the layout preview still describes gaps, border and radius", (layoutCanvas?.Accessible.description ?? "").indexOf(String(v.gapsIn)) >= 0
            && layoutCanvas?.Accessible.description === effects?.layoutSummary, { description: layoutCanvas?.Accessible.description ?? null });
        root.next();
    }

    function shotsStep() {
        const keys = [["windows", "hyprland.decoration.dim_strength"], ["windows", "hyprland.decoration.dim_special"]];
        const run = index => {
            if (index >= keys.length)
                return root.next();
            const [pageId, key] = keys[index];
            root.openPage(pageId, () => {
                const row = root.rowOn(pageId, key);
                root.saveShot(row, `row-760-${key}`, () => run(index + 1));
            });
        };
        run(0);
    }

    Component.onCompleted: {
        const component = Qt.createComponent(Qt.resolvedUrl("settings.qml"));
        if (component.status !== Component.Ready)
            return root.fatal(`settings.qml failed to load: ${component.errorString()}`);
        root.win = component.createObject(root, { width: 1100, height: 760 });
        root.steps = [root.quickSelectStep, root.narrowStep, root.decimalsStep, root.previewA11yStep, root.shotsStep];
        root.waitFor(() => root.win.pageReady, 30000, ok => {
            if (!ok)
                return root.fatal("the settings window never became ready");
            root.next();
        });
    }

    TestEvent {
        id: events
    }

    Timer {
        id: quitTimer
        interval: 200
        onTriggered: Qt.quit()
    }

    Component {
        id: laterComponent
        Timer {
            id: later
            property var action: null
            onTriggered: {
                const action = later.action;
                later.destroy();
                action();
            }
        }
    }

    Component {
        id: pollComponent
        Timer {
            id: poll
            property real deadline: 0
            property var test: null
            property var done: null
            interval: 100
            repeat: true
            onTriggered: {
                let ok = false;
                try {
                    ok = !!poll.test();
                } catch (error) {
                    ok = false;
                }
                if (ok || Date.now() > poll.deadline) {
                    poll.stop();
                    const done = poll.done;
                    poll.destroy();
                    done(ok);
                }
            }
        }
    }
}
