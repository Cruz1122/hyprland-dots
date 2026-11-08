//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
//@ pragma Env QT_SCALE_FACTOR=1

// Harness driver (run.sh --strict --allow-config-writes --hyprland-stub
// --driver): the Animations page in the real settings window, run by
// tests/test_animations_page.py. The test puts the hyprctl stub and the
// python3 shim (tests/harness/stubs) first on PATH, so generator calls,
// evals and reloads are counted from $PYTHON3_SHIM_LOG and $HYPRCTL_LOG.
// Steps (one "check" event each; any failure is a "fatal" event):
//   helpers       the widgets get the 5 backend helpers' results through SettingsStore.backends.animation
//   tab-order     Tab through a folded and an unfolded card; Space folds and unfolds
//   search        revealing a card (a search hit) unfolds it
//   not-loaded    without the loader in hyprland.lua (no animationsLoaded) every animation
//                 row and [Apply Minimal] is disabled with the reason, and a write runs nothing
//   unavailable   with the backend unavailable (here a foreign custom/shell-animations.lua)
//                 the preset shows "—" without a "Now:" note and [Apply Minimal] is disabled
//   loaded        the first card write passes the backend's animationsLoaded confirmation
//   curve-add     a new user curve through the library row
//   curve-spring  a user spring (hand-edited config) only gets a new name, never bezier points
//   preset        a preset is 1 generator call, 1 eval and at most 1 reload
//   default       Default empties the animations and keeps the curves
//   apply-minimal the [Apply Minimal] action of "Motion inside the shell" writes Minimal
//   undo          a preset over a custom state shows Undo; a second preset renames the bar;
//                 Undo restores the custom state in one batch
//   delete-used   deleting a curve that a card uses is refused
//   reduce-motion a changed control does not play the preview under reduceMotion, ▶ does
//   spring        a spring hides the duration and shows "≈ N ms (lo marca el muelle)"
//   game-mode     the cards show "Pausado por el Modo Juego" and no "Requires"
//   shots         a card unfolded at 760, 1100 and 1600 px: rows never overlap
import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import "modules/settings/components/CurveMath.js" as CurveMath
// @harness-imports

ShellRoot {
    id: root

    property var win: null
    property int failures: 0
    property var keys: null
    property var steps: []
    property int stepIndex: 0
    property var mark: null
    readonly property string hyprctlLog: Quickshell.env("HYPRCTL_LOG") ?? ""
    readonly property string shimLog: Quickshell.env("PYTHON3_SHIM_LOG") ?? ""
    readonly property string shotDir: Quickshell.env("SHOT_DIR") ?? ""
    readonly property string overridesFile: `${Quickshell.env("XDG_CONFIG_HOME")}/hypr/hyprland/shellOverrides/main.lua`
    readonly property string configurator: Quickshell.shellPath("scripts/hyprland/hyprconfigurator.py")
    readonly property var cardIds: ["windowsIn", "windowsOut", "windowsMove", "workspaces", "specialWorkspaceIn",
        "specialWorkspaceOut", "layersIn", "layersOut", "border", "zoomFactor"]

    function report(payload) {
        console.info(`[harness:report] ${JSON.stringify(payload)}`);
    }

    function fail(message) {
        root.failures++;
        root.report({ type: "fatal", message: message });
    }

    function check(step, ok, detail) {
        root.report(Object.assign({ type: "check", step: step, ok: !!ok }, detail ?? {}));
        if (!ok)
            root.fail(`${step}: ${JSON.stringify(detail ?? {})}`);
        return !!ok;
    }

    function findItem(item, name) {
        if (!item)
            return null;
        if (item.objectName === name)
            return item;
        for (const child of item.children) {
            const found = root.findItem(child, name);
            if (found)
                return found;
        }
        return null;
    }

    function findAll(item, prefix, acc) {
        if (!item)
            return acc;
        if (String(item.objectName ?? "").startsWith(prefix))
            acc.push(item);
        for (const child of item.children)
            root.findAll(child, prefix, acc);
        return acc;
    }

    // A card value as JSON in a fixed field order, to compare values
    // whatever their key order.
    function canon(value) {
        return value ? JSON.stringify({ enabled: value.enabled, speed: value.speed, curve: value.curve, style: value.style }) : String(value);
    }

    function backend() {
        return SettingsStore.backends?.animation ?? null;
    }

    function page() {
        return root.rowOn("animation.windowsIn")?.page ?? null;
    }

    // The row of `key` on the Animations page (Quick shows the preset too).
    function rowOn(key, pageId) {
        return root.findAll(root.win.contentItem, "row:" + key, []).find(r => r.objectName === "row:" + key && r.page?.pageId === (pageId ?? "animations")) ?? null;
    }

    function openPage(pageId, done) {
        root.win.currentPage = root.win.pages.findIndex(p => p.id === pageId);
        root.waitFor(() => root.win.pageReady && root.win.pages[root.win.currentPage]?.id === pageId, 4000, done);
    }

    function waitFor(check, timeoutMs, done) {
        pollComponent.createObject(root, { deadline: Date.now() + timeoutMs, check: check, done: done }).start();
    }

    function later(ms, done) {
        root.waitFor(() => false, ms, () => done());
    }

    // Waits until the backend is idle, past the reload grace (a fallback
    // reload would have run) and idle again.
    function settle(done) {
        const b = root.backend();
        root.later(500, () => root.waitFor(() => !b.busy, 15000, idle => root.later(b.reloadGraceMs + 900, () => root.waitFor(() => !b.busy, 15000, again => done(idle && again)))));
    }

    function run(argv, done) {
        const proc = procComponent.createObject(root, { command: argv });
        proc.exited.connect(code => {
            proc.destroy();
            done(code);
        });
        proc.running = true;
    }

    function writeText(path, text) {
        const view = writerComponent.createObject(root, { path: path });
        view.setText(text);
        view.destroy();
    }

    function readText(path) {
        const view = readerComponent.createObject(root, { path: path });
        const text = view.text();
        view.destroy();
        return text ?? "";
    }

    function lines(path) {
        return path.length > 0 ? root.readText(path).split("\n").filter(l => l.length > 0) : [];
    }

    function counts() {
        const hypr = root.lines(root.hyprctlLog);
        const shim = root.lines(root.shimLog);
        return {
            reloads: hypr.filter(l => l.trim() === "reload config-only").length,
            evals: hypr.filter(l => l.startsWith("eval ")).length,
            generatorCalls: shim.filter(l => l.includes("animationsgen.py") && l.includes("--apply-json")).length
        };
    }

    function begin() {
        root.mark = root.counts();
    }

    function since() {
        const now = root.counts();
        return {
            reloads: now.reloads - root.mark.reloads,
            evals: now.evals - root.mark.evals,
            generatorCalls: now.generatorCalls - root.mark.generatorCalls
        };
    }

    function fileText() {
        return root.readText(root.backend().animationsFile);
    }

    function animationLines() {
        return root.fileText().split("\n").filter(l => l.startsWith("hl.animation("));
    }

    function focusName() {
        let item = root.win.activeFocusItem;
        for (let p = item; p; p = p.parent) {
            const name = String(p.objectName ?? "");
            if (name.length > 0 && !name.startsWith("row:"))
                return name;
            if (name.startsWith("row:"))
                break;
        }
        return item ? `<${item}>` : "<none>";
    }

    function focusRow() {
        for (let p = root.win.activeFocusItem; p; p = p.parent) {
            if (String(p.objectName ?? "").startsWith("row:"))
                return p.objectName.slice(4);
        }
        return "";
    }

    function key(code) {
        root.keys.keyClick(code);
    }

    function saveShot(name, done) {
        // The window's contentItem cannot be grabbed; its shell (filling it) can.
        const frame = root.win.contentItem.children[0];
        const started = root.shotDir.length > 0 && frame.grabToImage(result => {
            result.saveToFile(`${root.shotDir}/${name}.png`);
            done();
        });
        if (!started)
            done();
    }

    function next() {
        if (root.stepIndex >= root.steps.length) {
            root.report({ type: "done", failures: root.failures });
            Qt.quit();
            return;
        }
        const step = root.steps[root.stepIndex++];
        root.report({ type: "step", name: step.name });
        step.run();
    }

    // ------------------------------------------------------------- helpers

    function helpersStep() {
        const b = root.backend();
        const card = root.rowOn("animation.windowsIn");
        const preset = root.rowOn("animation.preset");
        const library = root.rowOn("animation.curves");
        root.check("helpers: the rows exist", !!b && !!card && !!preset && !!library, {});
        if (!b || !card || !preset || !library) {
            root.next();
            return;
        }
        root.check("helpers: summaryParts reaches the card", JSON.stringify(card.parts) === JSON.stringify(b.summaryParts("windowsIn")) && card.parts !== null, { parts: card.parts });
        root.check("helpers: the summary is translated and joined", card.summary === "Emerger 80 % · 300 ms · Arranque rápido, frenada suave", { summary: card.summary });
        root.check("helpers: curveCatalog reaches the card", card.catalog.length > 0 && JSON.stringify(card.catalog) === JSON.stringify(b.curveCatalog()), { curves: card.catalog.length });
        root.check("helpers: styleOptions reaches the card", JSON.stringify(card.styleChoices.map(c => c.kind)) === JSON.stringify(b.styleOptions("windowsIn").map(o => o.kind)), {
            kinds: card.styleChoices.map(c => c.kind) });
        root.check("helpers: presets reach the preset row", JSON.stringify(preset.options.map(o => o.value)) === JSON.stringify(b.presets().map(p => p.value)), {
            options: preset.options.map(o => o.value) });
        const used = b.curveUsage("emphasizedDecel");
        root.check("helpers: curveUsage reaches the curve library", used.length > 0 && library.usageLabels("emphasizedDecel").length === used.length, {
            used: used, labels: library.usageLabels("emphasizedDecel") });
        const panelSummaries = ["layersIn", "layersOut"].map(id => root.rowOn(`animation.${id}`).summary);
        root.check("helpers: panel card summaries leave out the style", panelSummaries.every(t => t.length > 0 && t.indexOf("Emerger") < 0 && t.indexOf(" ms") > 0), { summaries: panelSummaries });
        root.check("helpers: panel cards and details have no style control", ["layersIn", "layersOut", "border", "zoomFactor"].every(id => root.rowOn(`animation.${id}`).styleChoices.length === 0), {});
        root.next();
    }

    // ----------------------------------------------------------- tab-order

    function tabStep() {
        const first = root.rowOn("animation.windowsIn");
        const second = root.rowOn("animation.windowsOut");
        first.unfolded = false;
        second.unfolded = false;
        const fold = root.findItem(first, "foldToggle");
        fold.forceActiveFocus(Qt.TabFocusReason);
        const seen = [`${root.focusRow()}/${root.focusName()}`];
        for (let i = 0; i < 3; i++) {
            root.key(Qt.Key_Tab);
            seen.push(`${root.focusRow()}/${root.focusName()}`);
        }
        root.check("tab-order: a folded card", JSON.stringify(seen) === JSON.stringify([
            "animation.windowsIn/foldToggle", "animation.windowsIn/playButton", "animation.windowsIn/enableSwitch", "animation.windowsOut/foldToggle"]), { seen: seen });
        root.key(Qt.Key_Space);
        root.waitFor(() => !!root.findItem(second, "animationPreview"), 3000, unfolded => {
            root.check("tab-order: Space unfolds the card", unfolded && second.unfolded, {});
            // The unfolded controls show the card's own value (a details
            // component that lost its row would show 50 ms and "No animation").
            const value = SettingsStore.value("animation.windowsOut");
            const shown = {
                ms: root.findItem(second, "durationSlider")?.value,
                curve: root.findItem(second, "curvePicker")?.value,
                style: root.findItem(second, "styleCombo")?.currentText,
                previewEnabled: root.findItem(second, "animationPreview")?.enabled
            };
            root.check("unfolded: the controls show the card's value", shown.ms === Math.round(value.speed * 100) && shown.curve === value.curve
                && shown.style === "Emerger" && shown.previewEnabled === true, { shown: shown, value: value });
            const order = [`${root.focusRow()}/${root.focusName()}`];
            for (let i = 0; i < 7; i++) {
                root.key(Qt.Key_Tab);
                order.push(`${root.focusRow()}/${root.focusName()}`);
            }
            root.check("tab-order: an unfolded card", JSON.stringify(order.slice(0, 7)) === JSON.stringify([
                "animation.windowsOut/foldToggle", "animation.windowsOut/playButton", "animation.windowsOut/enableSwitch",
                "animation.windowsOut/durationSlider", "animation.windowsOut/curvePicker", "animation.windowsOut/styleCombo",
                "animation.windowsOut/percentSlider"]) && order[7].startsWith("animation.windowsMove/"), {
                order: order, style: (() => { const c = root.findItem(second, "styleCombo"); return c ? { visible: c.visible, policy: c.focusPolicy, onTab: c.activeFocusOnTab, enabled: c.enabled } : null; })() });
            const toggle = root.findItem(second, "foldToggle");
            toggle.forceActiveFocus(Qt.TabFocusReason);
            root.check("tab-order: the focus ring shows", toggle.visualFocus === true, {});
            root.key(Qt.Key_Return);
            root.check("tab-order: Enter folds the card", !second.unfolded, {});
            root.check("tab-order: the card has an accessible name and description", second.Accessible.name === "Cerrar" && second.Accessible.description.indexOf(second.summary) === 0, {
                name: second.Accessible.name, description: second.Accessible.description });
            root.next();
        });
    }

    // ------------------------------------------------------------- search

    function searchStep() {
        const row = root.rowOn("animation.zoomFactor");
        row.unfolded = false;
        const hit = SettingsRegistry.search("zoom de la pantalla").find(r => r.kind === "entry");
        root.check("search: the card is a search result", hit?.key === "animation.zoomFactor", { hit: hit?.key ?? null });
        root.win.reveal("animation.zoomFactor");
        root.waitFor(() => row.unfolded && !!root.findItem(row, "animationPreview"), 4000, ok => {
            root.check("search: revealing the card unfolds it", ok, {});
            row.unfolded = false;
            root.next();
        });
    }

    // ---------------------------------------------------------- not-loaded

    // hyprland.lua without the require (here: commented out) has no
    // animationsLoaded capability: Hyprland would never load what the page
    // writes, so the rows say why they are disabled and nothing is written.
    function notLoadedStep() {
        const b = root.backend();
        const reason = "Hyprland todavía no carga los ajustes de animación: actualiza los dotfiles";
        const keys = root.cardIds.map(id => `animation.${id}`).concat(["animation.preset", "animation.curves"]);
        const rows = () => keys.map(k => root.rowOn(k));
        const action = root.rowOn("action.animations.applyMinimal");
        const original = root.readText(b.hyprlandFile);
        const commented = original.replace('    pcall(require, "custom.shell-animations")', '    -- pcall(require, "custom.shell-animations")');
        root.check("not-loaded: the rows start enabled with the loader", commented !== original && SettingsStore.hasCapability("animationsLoaded")
            && rows().every(r => r?.rowEnabled) && action?.rowEnabled === true, {});
        root.writeText(b.hyprlandFile, commented);
        b.hyprlandEvents.onRawEvent({ name: "configreloaded" });
        root.waitFor(() => !SettingsStore.hasCapability("animationsLoaded") && rows().every(r => !r.rowEnabled), 5000, dropped => {
            const bad = rows().filter(r => r.rowEnabled || r.disabledReason !== reason || r.requires !== null);
            root.check("not-loaded: every animation row is disabled with the reason", dropped && bad.length === 0, {
                bad: bad.map(r => ({ key: r.settingKey, enabled: r.rowEnabled, reason: r.disabledReason, requires: r.requires })) });
            root.check("not-loaded: [Apply Minimal] is disabled with the reason", !action.rowEnabled && action.disabledReason === reason, {
                enabled: action.rowEnabled, reason: action.disabledReason });
            root.begin();
            const card = root.rowOn("animation.border");
            const wrote = SettingsStore.write("animation.border", Object.assign({}, card.value, { speed: card.value.speed + 1 }));
            root.later(900, () => {
                const counts = root.since();
                root.check("not-loaded: a write is refused and runs nothing", wrote === false && counts.generatorCalls === 0 && counts.evals === 0
                    && !card.modified, Object.assign({ wrote: wrote }, counts));
                root.writeText(b.hyprlandFile, original);
                b.hyprlandEvents.onRawEvent({ name: "configreloaded" });
                root.waitFor(() => SettingsStore.hasCapability("animationsLoaded") && rows().every(r => r.rowEnabled) && action.rowEnabled, 5000, back => {
                    root.check("not-loaded: the loader back enables the rows again", back, {});
                    root.settle(() => root.next());
                });
            });
        });
    }

    // --------------------------------------------------------- unavailable

    // An unavailable backend knows no preset: the row shows "—" and no
    // "Now: …" (an empty managed state would read as Default), and
    // [Apply Minimal] cannot offer a write that can only fail. The foreign
    // file is the same `available === false` path as Hyprland not running.
    function unavailableStep() {
        const b = root.backend();
        const preset = root.rowOn("animation.preset");
        const action = root.rowOn("action.animations.applyMinimal");
        root.check("unavailable: with the backend the preset shows its note", preset.available && preset.optionNote.length > 0 && action.rowEnabled, {
            note: preset.optionNote, action: action.rowEnabled });
        b.foreign = true;
        root.waitFor(() => !preset.available && !action.rowEnabled, 3000, gone => {
            root.check("unavailable: the preset shows — and no Now note", gone && preset.showPlaceholder && preset.optionNote === ""
                && preset.Accessible.description.indexOf("Ahora:") < 0, {
                placeholder: preset.showPlaceholder, note: preset.optionNote, description: preset.Accessible.description });
            // Without the page's gating the registry capability would still
            // disable the row, but with the "not loaded yet" reason, which is
            // untrue here: the row must say it is not available instead.
            const notLoaded = "Hyprland todavía no carga los ajustes de animación: actualiza los dotfiles";
            root.check("unavailable: [Apply Minimal] is disabled", gone && !action.rowEnabled && action.disabledReason === "No disponible"
                && action.disabledReason !== notLoaded && action.Accessible.description.indexOf(notLoaded) < 0, {
                enabled: action.rowEnabled, reason: action.disabledReason, description: action.Accessible.description });
            b.foreign = false;
            root.waitFor(() => preset.available && action.rowEnabled && preset.optionNote.length > 0, 3000, back => {
                root.check("unavailable: the backend back restores the note and the action", back, {});
                root.next();
            });
        });
    }

    // -------------------------------------------------------------- loaded

    // The backend confirms once, after the first card write, that Hyprland
    // loaded the file (`hyprctl -j animations`). The test serves windowsIn as
    // this write leaves it, so the confirmation passes without a warning and
    // later writes are not compared with the static fixture.
    function loadedStep() {
        const b = root.backend();
        const card = root.rowOn("animation.windowsIn");
        const before = card.value;
        card.commit({ enabled: true, speed: 2, curve: "emphasizedDecel", style: "popin 85%" });
        root.waitFor(() => b._confirmed === true && !b.busy, 20000, confirmed => {
            root.check("loaded: Hyprland reports the first written card", confirmed && SettingsStore.hasCapability("animationsLoaded"), {});
            SettingsStore.reset("animation.windowsIn");
            root.settle(idle => {
                root.check("loaded: the card is back to the dotfiles value", idle && root.canon(card.value) === root.canon(before) && !card.modified, { value: card.value });
                root.next();
            });
        });
    }

    // ---------------------------------------------------------- curve-add

    function curveAddStep() {
        const library = root.rowOn("animation.curves");
        library.startAdd();
        root.check("curve-add: the editor opens with a generated name", library.editing?.name === "ii_curve_1" && library.editLabel === "Mi curva 1"
            && root.findItem(library, "curveEditorPanel").visible, { editing: library.editing, label: library.editLabel });
        root.begin();
        library.save([0.2, 0, 0, 1]);
        root.settle(idle => {
            const curves = SettingsStore.value("animation.curves");
            root.check("curve-add: the curve is saved", idle && curves.length === 1 && curves[0].name === "ii_curve_1"
                && root.fileText().indexOf('hl.curve("ii_curve_1"') >= 0, Object.assign({ curves: curves }, root.since()));
            root.next();
        });
    }

    // -------------------------------------------------------- curve-spring

    // The editor only makes beziers; a user spring from a hand-edited or
    // imported config keeps its mass/stiffness/damping when renamed.
    function curveSpringStep() {
        const library = root.rowOn("animation.curves");
        const spring = { name: "ii_curve_2", type: "spring", label: "Mi muelle", mass: 1, stiffness: 200, damping: 20 };
        SettingsStore.write("animation.curves", SettingsStore.value("animation.curves").concat([spring]));
        root.settle(() => {
            const stored = SettingsStore.value("animation.curves").find(c => c.name === "ii_curve_2");
            library.startEdit(stored);
            root.check("curve-spring: a spring opens without the bezier editor", !!stored && library.editing?.spring === true
                && root.findItem(library, "curveSpringNote").visible && !root.findItem(library, "curveEditor").visible, {
                stored: stored, editing: library.editing });
            library.editLabel = "Muelle nuevo";
            library.save([0.2, 0, 0, 1]);
            root.settle(() => {
                const saved = SettingsStore.value("animation.curves").find(c => c.name === "ii_curve_2");
                root.check("curve-spring: renaming keeps the spring", !!saved && saved.type === "spring" && saved.label === "Muelle nuevo"
                    && saved.mass === 1 && saved.stiffness === 200 && saved.damping === 20 && saved.points === undefined, { saved: saved });
                library.deleteCurve("ii_curve_2");
                root.settle(() => {
                    root.check("curve-spring: the spring is removed again", SettingsStore.value("animation.curves").length === 1, {
                        curves: SettingsStore.value("animation.curves") });
                    root.next();
                });
            });
        });
    }

    // -------------------------------------------------------------- preset

    function presetStep() {
        const row = root.rowOn("animation.preset");
        root.check("preset: starts from Default", row.value === "default", { value: row.value });
        root.begin();
        root.findItem(row, "preset:agile").clicked();
        root.settle(idle => {
            const counts = root.since();
            root.check("preset: one generator call, one eval, at most one reload", idle && counts.generatorCalls === 1 && counts.evals === 1 && counts.reloads <= 1, counts);
            root.check("preset: the row shows the preset", row.value === "agile" && row.optionNote.length > 0, { value: row.value });
            root.check("preset: no Undo bar over a preset", !root.findItem(row, "presetUndoBar").visible, {});
            root.check("preset: every card is in the file", root.cardIds.every(id => root.animationLines().some(l => l.indexOf(`leaf = "${id}"`) >= 0)), { lines: root.animationLines().length });
            // The alias on Quick (registry/quick.json, section "look") is the
            // same preset widget and shows the same value.
            const note = row.optionNote;
            root.openPage("quick", quickReady => {
                const quick = root.rowOn("animation.preset", "quick");
                root.check("preset: the Quick alias is a preset row", quickReady && !!quick && quick.settingKey === "animation.preset"
                    && typeof quick.applyPreset === "function" && (quick.options?.length ?? 0) >= 5
                    && !!root.findItem(quick, "preset:agile") && quick.value === "agile" && quick.optionNote === note, {
                    ready: quickReady, found: !!quick, options: quick?.options?.length ?? 0, value: quick?.value, note: quick?.optionNote });
                root.openPage("animations", back => {
                    root.check("preset: back on the Animations page", back && !!root.rowOn("animation.windowsIn"), {});
                    root.next();
                });
            });
        });
    }

    function defaultStep() {
        const row = root.rowOn("animation.preset");
        root.begin();
        root.findItem(row, "preset:default").clicked();
        root.settle(idle => {
            const counts = root.since();
            const text = root.fileText();
            root.check("default: no animation lines are left", idle && root.animationLines().length === 0, { lines: root.animationLines() });
            root.check("default: the curves stay", text.indexOf('hl.curve("ii_curve_1"') >= 0 && SettingsStore.value("animation.curves").length === 1, {});
            root.check("default: one generator call", counts.generatorCalls === 1 && counts.reloads <= 1, counts);
            root.check("default: the row shows Default", row.value === "default", { value: row.value });
            root.next();
        });
    }

    // ------------------------------------------------------- apply-minimal

    // [Apply Minimal] in "Motion inside the shell" writes the Minimal preset
    // (one change set), then Default puts the dotfiles animations back.
    function applyMinimalStep() {
        const action = root.rowOn("action.animations.applyMinimal");
        const preset = root.rowOn("animation.preset");
        root.begin();
        action.run();
        root.settle(idle => {
            const counts = root.since();
            root.check("apply-minimal: the button writes the Minimal preset", idle && preset.value === "minimal" && counts.generatorCalls === 1 && counts.evals === 1
                && !root.findItem(preset, "presetUndoBar").visible, Object.assign({ value: preset.value }, counts));
            preset.applyPreset("default");
            root.settle(() => {
                root.check("apply-minimal: Default again", preset.value === "default" && root.animationLines().length === 0, { value: preset.value });
                root.next();
            });
        });
    }

    // ---------------------------------------------------------------- undo

    function undoStep() {
        const row = root.rowOn("animation.preset");
        const card = root.rowOn("animation.windowsIn");
        const custom = Object.assign({}, card.value, { speed: 2.5 });
        SettingsStore.write("animation.windowsIn", custom);
        root.settle(() => {
            root.check("undo: a card change makes the state custom", row.value === "custom" && root.findItem(row, "preset:custom")?.enabled === false, { value: row.value });
            row.applyPreset("smooth");
            root.settle(() => {
                const bar = root.findItem(row, "presetUndoBar");
                root.check("undo: a preset over a custom state shows Undo", row.value === "smooth" && bar.visible, { value: row.value });
                // A second preset inside the 10 s keeps the snapshot but
                // names the preset now applied.
                row.applyPreset("agile");
                const text = root.findItem(row, "presetUndoText")?.text ?? "";
                root.check("undo: a second preset renames the Undo bar", row.undoLabel === "Ágil" && text.indexOf("«Ágil»") === 0 && bar.visible, {
                    label: row.undoLabel, text: text });
                root.settle(() => {
                    root.check("undo: the second preset is applied", row.value === "agile" && bar.visible, { value: row.value });
                    root.begin();
                    root.findItem(row, "presetUndo").clicked();
                    root.settle(idle => {
                        const counts = root.since();
                        const lines = root.animationLines();
                        root.check("undo: one batch", idle && counts.generatorCalls === 1 && counts.evals <= 1 && counts.reloads <= 1, counts);
                        root.check("undo: the previous cards are back", row.value === "custom" && root.canon(SettingsStore.value("animation.windowsIn")) === root.canon(custom)
                            && lines.length === 2 && lines.every(l => l.indexOf('leaf = "windowsIn"') >= 0 || l.indexOf('leaf = "fadeIn"') >= 0), {
                            lines: lines, value: row.value, card: SettingsStore.value("animation.windowsIn"), expected: custom });
                        root.check("undo: the bar goes away", !bar.visible, {});
                        root.next();
                    });
                });
            });
        });
    }

    // --------------------------------------------------------- delete-used

    function deleteUsedStep() {
        const library = root.rowOn("animation.curves");
        const card = root.rowOn("animation.windowsIn");
        SettingsStore.write("animation.windowsIn", Object.assign({}, card.value, { curve: "ii_curve_1" }));
        root.settle(() => {
            root.begin();
            const deleted = library.deleteCurve("ii_curve_1");
            root.later(900, () => {
                const usage = root.findAll(library, "curveUsage", []).map(t => t.text);
                root.check("delete-used: the delete is refused", deleted === false && SettingsStore.value("animation.curves").length === 1
                    && root.findItem(library, "curveRefusal").visible && root.since().generatorCalls === 0, { refusal: library.refusal });
                root.check("delete-used: the library says who uses it", usage.some(t => t === "La usan: Ventanas › Abrir"), { usage: usage });
                SettingsStore.write("animation.windowsIn", Object.assign({}, card.value, { curve: "emphasizedDecel" }));
                root.settle(() => root.next());
            });
        });
    }

    // -------------------------------------------------------- reduce-motion

    function reduceMotionStep() {
        const row = root.rowOn("animation.windowsMove");
        SettingsStore.write("appearance.animations.reduceMotion", true);
        row.unfolded = true;
        root.waitFor(() => row.reduceMotion && !!root.findItem(row, "animationPreview"), 4000, ready => {
            const preview = root.findItem(row, "animationPreview");
            // Every start is recorded, so neither check depends on when it
            // samples: a wrong replay that already ended still counts, and
            // a ▶ replay is seen however late the event loop runs.
            const starts = { count: 0 };
            const onStart = () => { if (preview.playing) starts.count++; };
            preview.playingChanged.connect(onStart);
            row.commitField("speed", 2.2);
            root.later(400, () => {
                root.check("reduce-motion: a changed control does not play the preview", ready && starts.count === 0 && !preview.playing && preview.progress === 1, {
                    starts: starts.count, playing: preview.playing, progress: preview.progress });
                root.findItem(row, "playButton").clicked();
                root.later(60, () => {
                    preview.playingChanged.disconnect(onStart);
                    root.check("reduce-motion: ▶ plays it", starts.count >= 1, {
                        starts: starts.count, progress: preview.progress, enabled: preview.enabled, card: row.card, rowEnabled: row.enabled, details: !!row.findDetails });
                    SettingsStore.reset("appearance.animations.reduceMotion");
                    root.waitFor(() => !row.reduceMotion && !preview.playing, 4000, () => {
                        // Record any start: under load a 260 ms replay can
                        // finish before a fixed delay ends, so polling
                        // `playing` once would flake.
                        const seen = { started: false };
                        const onPlaying = () => { if (preview.playing) seen.started = true; };
                        preview.playingChanged.connect(onPlaying);
                        row.commitField("speed", 2.6);
                        root.later(150, () => {
                            preview.playingChanged.disconnect(onPlaying);
                            root.check("reduce-motion: without it a change replays the preview", seen.started || preview.playing === true, {
                                playing: preview.playing, progress: preview.progress });
                            SettingsStore.reset("animation.windowsMove");
                            row.unfolded = false;
                            root.settle(() => root.next());
                        });
                    });
                });
            });
        });
    }

    // --------------------------------------------------------------- spring

    // A spring hides the duration slider and shows its settle time, rounded
    // to 10 ms, in the card and in the summary.
    function springStep() {
        const row = root.rowOn("animation.windowsMove");
        row.unfolded = true;
        row.commitField("curve", "ii_spring_soft");
        root.waitFor(() => row.spring && !!root.findItem(row, "durationValue"), 4000, ready => {
            // Computed apart from the row: the catalog's ii_spring_soft through
            // CurveMath (647 ms, shown as 650; the Python twin in
            // tests/test_curve_math agrees within a few ms).
            const spring = root.backend().curveCatalog().find(c => c.name === "ii_spring_soft");
            const settle = Math.round(CurveMath.springSettleMs(spring) / 10) * 10;
            const expected = `≈ ${settle} ms (lo marca el muelle)`;
            const shown = root.findItem(row, "durationValue")?.text ?? "";
            root.check("spring: the card shows the spring's own time", ready && settle === 650 && shown === expected
                && root.findItem(row, "durationSlider").visible === false && row.summary.indexOf(expected) >= 0, {
                shown: shown, expected: expected, summary: row.summary });
            SettingsStore.reset("animation.windowsMove");
            row.unfolded = false;
            root.settle(() => root.next());
        });
    }

    // ------------------------------------------------------------ game-mode

    function configReloaded() {
        SettingsStore.backends?.hyprland?.hyprlandEvents.onRawEvent({ name: "configreloaded" });
        root.backend()?.hyprlandEvents.onRawEvent({ name: "configreloaded" });
    }

    function gameModeStep() {
        const expected = "Pausado por el Modo Juego";
        const keys = root.cardIds.map(id => `animation.${id}`).concat(["animation.preset"]);
        const rows = () => keys.map(k => root.rowOn(k));
        root.run(["mkdir", "-p", root.overridesFile.replace(/\/[^/]*$/, "")], () => root.run(["python3", root.configurator, "--file", root.overridesFile, "--set", "animations:enabled", "0"], code => {
            root.configReloaded();
            root.waitFor(() => rows().every(r => r?.statusNote === expected), 8000, ok => {
                const bad = rows().filter(r => r.statusNote !== expected || r.requires !== null || !r.rowEnabled || root.findAll(r, "chip:", []).some(c => c.visible && c.objectName.indexOf("requires") >= 0));
                root.check("game-mode: the cards show the note and no Requires", code === 0 && ok && bad.length === 0, {
                    bad: bad.map(r => ({ key: r.settingKey, note: r.statusNote, requires: r.requires, enabled: r.rowEnabled })) });
                root.check("game-mode: the page banner shows", root.rowOn("info.animations.gameMode")?.visible === true, {});
                root.run(["python3", root.configurator, "--file", root.overridesFile, "--reset", "animations:enabled"], () => {
                    root.configReloaded();
                    root.waitFor(() => rows().every(r => r.statusNote === ""), 8000, gone => {
                        root.check("game-mode: the note goes away with Game Mode", gone, {});
                        root.settle(() => root.next());
                    });
                });
            });
        }));
    }

    // --------------------------------------------------------------- shots

    readonly property var shotSizes: [{ w: 760, h: 720 }, { w: 1100, h: 760 }, { w: 1600, h: 900 }]

    function overlaps() {
        const rows = root.findAll(root.page(), "row:", []).filter(r => r.visible && r.width > 0 && r.height > 0);
        const rects = rows.map(r => {
            const p = r.mapToItem(root.win.contentItem, 0, 0);
            return { key: r.settingKey, x: p.x, y: p.y, w: r.width, h: r.height, item: r };
        });
        const out = [];
        for (let i = 0; i < rects.length; i++) {
            for (let j = i + 1; j < rects.length; j++) {
                const a = rects[i];
                const b = rects[j];
                const ix = Math.min(a.x + a.w, b.x + b.w) - Math.max(a.x, b.x);
                const iy = Math.min(a.y + a.h, b.y + b.h) - Math.max(a.y, b.y);
                if (ix > 1 && iy > 1)
                    out.push(`${a.key} x ${b.key}`);
            }
        }
        const wide = rects.filter(r => r.x < -1 || r.x + r.w > root.win.width + 1).map(r => r.key);
        return { overlaps: out, overflowX: wide };
    }

    function shotsStep() {
        const row = root.rowOn("animation.windowsIn");
        const shoot = index => {
            if (index >= root.shotSizes.length) {
                root.win.width = 1100;
                root.win.height = 760;
                root.next();
                return;
            }
            const size = root.shotSizes[index];
            root.win.width = size.w;
            root.win.height = size.h;
            row.unfolded = true;
            root.later(900, () => {
                root.page().scrollToItem(row);
                root.later(900, () => {
                    const found = root.overlaps();
                    const details = root.findItem(row, "animationDetails");
                    const preview = root.findItem(row, "animationPreview");
                    const p = preview.mapToItem(row, 0, 0);
                    root.check("shots: rows do not overlap with a card unfolded", found.overlaps.length === 0 && found.overflowX.length === 0, Object.assign({ size: `${size.w}x${size.h}` }, found));
                    root.check("shots: the unfolded card fits its row", details.visible && p.x >= 0 && p.x + preview.width <= row.width + 1 && p.y + preview.height <= row.height + 1, {
                        size: `${size.w}x${size.h}`, columns: details.item?.columns ?? null });
                    root.saveShot(`animations-unfolded-${size.w}x${size.h}`, () => shoot(index + 1));
                });
            });
        };
        shoot(0);
    }

    function start() {
        root.keys = Qt.createQmlObject("import QtQuick; import QtTest; TestCase { when: false }", root.win.contentItem, "harnessKeys");
        root.steps = [
            { name: "helpers", run: root.helpersStep },
            { name: "tab-order", run: root.tabStep },
            { name: "search", run: root.searchStep },
            { name: "not-loaded", run: root.notLoadedStep },
            { name: "unavailable", run: root.unavailableStep },
            { name: "loaded", run: root.loadedStep },
            { name: "curve-add", run: root.curveAddStep },
            { name: "curve-spring", run: root.curveSpringStep },
            { name: "preset", run: root.presetStep },
            { name: "default", run: root.defaultStep },
            { name: "apply-minimal", run: root.applyMinimalStep },
            { name: "undo", run: root.undoStep },
            { name: "delete-used", run: root.deleteUsedStep },
            { name: "reduce-motion", run: root.reduceMotionStep },
            { name: "spring", run: root.springStep },
            { name: "game-mode", run: root.gameModeStep },
            { name: "shots", run: root.shotsStep }
        ];
        root.report({ type: "start", steps: root.steps.map(s => s.name) });
        root.openPage("animations", ready => {
            if (!root.check("start: the Animations page opens", ready && !!root.rowOn("animation.windowsIn"), {})) {
                root.report({ type: "done", failures: root.failures });
                Qt.quit();
                return;
            }
            root.next();
        });
    }

    Component.onCompleted: {
        const component = Qt.createComponent(Qt.resolvedUrl("settings.qml"));
        if (component.status !== Component.Ready) {
            root.fail(`settings.qml failed to load: ${component.errorString()}`);
            Qt.callLater(Qt.quit);
            return;
        }
        root.win = component.createObject(root, { width: 1100, height: 760 });
    }

    Component {
        id: procComponent
        Process {}
    }

    Component {
        id: readerComponent
        FileView {
            blockLoading: true
            printErrors: false
        }
    }

    Component {
        id: writerComponent
        FileView {
            blockWrites: true
            printErrors: false
        }
    }

    Component {
        id: pollComponent
        Timer {
            id: poll
            property real deadline: 0
            property var check: null
            property var done: null
            interval: 100
            repeat: true
            onTriggered: {
                const ok = poll.check();
                if (ok || Date.now() > poll.deadline) {
                    poll.stop();
                    const done = poll.done;
                    poll.destroy();
                    done(ok);
                }
            }
        }
    }

    // Starts once the window, the config, the animation backend and the
    // dotfiles base are ready.
    Timer {
        interval: 100
        repeat: true
        running: true
        property int waited: 0
        onTriggered: {
            waited += interval;
            const b = root.backend();
            if (Config.ready && root.win?.pageReady && b?.available && b.base !== null) {
                stop();
                startDelay.start();
            } else if (waited > 30000) {
                stop();
                root.fail(`settings never became ready (animation backend: ${b?.unavailableReason ?? "missing"}, base: ${b?.base !== null})`);
                root.report({ type: "done", failures: root.failures });
                Qt.quit();
            }
        }
    }

    Timer {
        id: startDelay
        interval: 1500
        onTriggered: root.start()
    }
}
