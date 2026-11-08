//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
//@ pragma Env QT_QUICK_FLICKABLE_WHEEL_DECELERATION=10000
//@ pragma Env QT_SCALE_FACTOR=1

// Harness driver (run.sh --driver) for the comprehension layer of the
// settings app (docs/settings.md "Rows"). tests/test_settings_comprehension.py
// runs it twice:
//
// With --hyprland-stub (Hyprland rows available):
//   option-texts the registry has no option descriptions or slider captions
//                yet, so this step adds test texts to entries of pages not
//                created yet: select and segmented rows show "Now: <the
//                selected option's description>", a slider shows its
//                minLabel/maxLabel under the track;
//   help-search  a word found only in a help text: activating the result
//                opens the row's page, highlights the row and opens its help;
//   help-keys    the "?" toggle takes keyboard focus, is named "Help: <label>"
//                and Space/Enter open and close the help;
//   requires     a "Requires …" chip (a row disabled by another setting) is a
//                link: Enter on it reveals and highlights the target row,
//                no lock line repeats it, and Space on a chip whose target
//                is on another page (a test enabledWhen) opens that page;
//   chips        no row of the visited pages shows more than 2 chips.
// Without Hyprland:
//   backend-down every section of the Windows page with Hyprland rows shows
//                one banner, and those rows show "—" instead of a control.
// Results are "[harness:report]" lines; any failure is a "fatal" event.
import QtQuick
import Quickshell
import qs.modules.common
// @harness-imports

ShellRoot {
    id: root

    property var win: null
    property int failures: 0
    property var keys: null
    property var steps: []
    property int stepIndex: 0

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

    function currentPageId() {
        return root.win.pages[root.win.currentPage]?.id ?? "";
    }

    function openPage(pageId, done) {
        root.win.currentPage = root.win.pages.findIndex(p => p.id === pageId);
        root.waitFor(() => root.win.pageReady && root.currentPageId() === pageId, 4000, done);
    }

    function rowFor(key) {
        return root.findItem(root.win.contentItem, "row:" + key);
    }

    // The row of `key` rendered by page `pageId` (other pages may show an
    // alias of the same key, with the same objectName).
    function rowOn(pageId, key) {
        return root.findAll(root.win.contentItem, "row:" + key, []).find(r => r.objectName === "row:" + key && r.page?.pageId === pageId) ?? null;
    }

    function waitFor(check, timeoutMs, done) {
        const timer = pollComponent.createObject(root, { deadline: Date.now() + timeoutMs, check: check, done: done });
        timer.start();
    }

    function saveShot(item, name, then) {
        const dir = Quickshell.env("SHOT_DIR");
        const started = !!dir && !!item && item.grabToImage(result => {
            result.saveToFile(`${dir}/${name}.png`);
            if (then)
                then();
        });
        if (!started && then)
            then();
    }

    // Key events go to the settings window's focus item (QtTest events).
    function key(code) {
        root.keys.keyClick(code);
    }

    // ----------------------------------------------------------- option-texts

    // Test texts (English source strings without a translation, shown as
    // they are) for entries of pages that do not exist yet: rows read the
    // registry entry when they are created.
    readonly property var optionRows: ["bar.cornerStyle", "bar.topLeftIcon"]
    readonly property string sliderKey: "hyprland.decoration.rounding_power"

    function optionTextsStep() {
        if (!root.check("option-texts: the pages are not created yet", root.optionRows.every(k => !root.rowOn("bar", k)) && !root.rowOn("windows", root.sliderKey))) {
            root.next();
            return;
        }
        for (const key of root.optionRows) {
            for (const option of SettingsRegistry.entry(key).options)
                option.description = `Test description of the option ${option.label}, long enough to wrap when the text column is narrow.`;
        }
        const slider = SettingsRegistry.entry(root.sliderKey);
        slider.minLabel = "Test round";
        slider.maxLabel = "Test square";
        root.openPage("bar", ready => {
            const run = index => {
                if (index >= root.optionRows.length) {
                    root.sliderStep();
                    return;
                }
                const row = root.rowOn("bar", root.optionRows[index]);
                const option = row ? SettingsRegistry.entry(row.settingKey).options.find(o => JSON.stringify(o.value) === JSON.stringify(row.value)) : null;
                const expected = option ? Translation.tr("Now: %1").arg(Translation.tr(option.description)) : "";
                const note = row ? root.findItem(row, "optionNote") : null;
                root.check("option-texts: the selected option's description shows as Now: …", ready && expected && row.optionNote === expected && note?.visible && note.text === expected, {
                    key: root.optionRows[index], optionNote: row?.optionNote ?? null, expected: expected });
                root.check("option-texts: the accessible description includes it", !!row && row.Accessible.description.indexOf(expected.replace(/[.\s]+$/, "")) >= 0, { key: root.optionRows[index] });
                root.saveShot(row, `option-note-${row?.settingKey}`, () => run(index + 1));
            };
            run(0);
        });
    }

    function sliderStep() {
        root.openPage("windows", ready => {
            const row = root.rowOn("windows", root.sliderKey);
            const scale = row ? root.findItem(row, "sliderScale") : null;
            const texts = [];
            const collect = item => {
                if (item.visible && typeof item.text === "string" && item.text.length > 0)
                    texts.push(item.text);
                for (const child of item.children)
                    collect(child);
            };
            if (scale)
                collect(scale);
            root.check("option-texts: the slider shows minLabel and maxLabel under the track", ready && scale?.visible && texts.includes("Test round") && texts.includes("Test square"), {
                key: root.sliderKey, texts: texts });
            root.check("option-texts: the default tick is drawn when the default is known", !!row && typeof row.defaultValue === "number" && root.findItem(row, "defaultTick")?.visible === true, {
                key: root.sliderKey, defaultValue: row?.defaultValue ?? null });
            root.check("option-texts: the reset text names the default", !!row && row.resetText === Translation.tr("Reset to %1").arg(Number(row.defaultValue).toFixed(1)), {
                resetText: row?.resetText ?? null });
            root.saveShot(row, "slider-captions", () => root.next());
        });
    }

    // ------------------------------------------------------------ help-search

    function fold(text) {
        return String(text).normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase();
    }

    // A word of a translated help text that the search finds only through
    // that help (fields == ["help"]) for that entry.
    function helpOnlyWord(nav) {
        for (const e of SettingsRegistry.allEntries()) {
            if (!e.help || !SettingsStore.isVisible(e.key))
                continue;
            const words = root.fold(Translation.tr(e.help)).split(/[^a-z0-9]+/).filter(w => w.length >= 7);
            for (const w of words) {
                nav.setQuery(w);
                const hit = nav.results.find(r => r.key === e.key);
                if (hit && hit.helpMatched && hit.fields.join() === "help")
                    return { word: w, key: e.key, pageId: hit.pageId };
            }
        }
        return null;
    }

    function helpSearchStep() {
        const nav = root.findItem(root.win.contentItem, "settingsNavigation");
        const target = nav ? root.helpOnlyWord(nav) : null;
        if (!root.check("help-search: word found only in a help text", target, { target: target })) {
            nav?.clearSearch();
            root.next();
            return;
        }
        SettingsSession.setHelpOpen(target.key, false);
        nav.setQuery(target.word);
        nav.activateResult(nav.results.findIndex(r => r.key === target.key));
        root.waitFor(() => {
            const row = root.rowFor(target.key);
            return root.currentPageId() === target.pageId && row?.visible && row.highlighted && row.helpOpen;
        }, 4000, ok => {
            const row = root.rowFor(target.key);
            const helpText = row ? root.findItem(row, "helpText") : null;
            root.check("help-search: reveal highlights the row and opens its help", ok && helpText?.visible, {
                word: target.word, key: target.key, page: root.currentPageId(),
                highlighted: row?.highlighted ?? null, helpOpen: row?.helpOpen ?? null, helpVisible: helpText?.visible ?? null
            });
            root.saveShot(row, "help-search-row", () => root.next());
        });
    }

    // ------------------------------------------------------------- help-keys

    function helpKeysStep() {
        const rows = root.findAll(root.win.contentItem, "row:", []).filter(r => r.visible && r.help && r.help.length > 0);
        const row = rows[0];
        if (!root.check("help-keys: a row with help on the current page", row, { page: root.currentPageId() })) {
            root.next();
            return;
        }
        const toggle = root.findItem(row, "helpToggle");
        SettingsSession.setHelpOpen(row.settingKey, false);
        toggle.forceActiveFocus(Qt.TabFocusReason);
        root.waitFor(() => toggle.activeFocus, 2000, focused => {
            root.check("help-keys: the toggle takes keyboard focus", focused && (toggle.focusPolicy & Qt.TabFocus), { key: row.settingKey });
            const expectedName = Translation.tr("Help: %1").arg(row.label);
            root.check("help-keys: accessible name", toggle.Accessible.name === expectedName, { name: toggle.Accessible.name, expected: expectedName });
            root.check("help-keys: collapsed by default", !row.helpOpen && !root.findItem(row, "helpText").visible, { key: row.settingKey });
            root.key(Qt.Key_Space);
            const openedBySpace = row.helpOpen && root.findItem(row, "helpText").visible;
            root.check("help-keys: Space opens the help", openedBySpace, { key: row.settingKey });
            root.key(Qt.Key_Return);
            root.check("help-keys: Enter closes it", !row.helpOpen, { key: row.settingKey });
            root.key(Qt.Key_Return);
            root.check("help-keys: Enter opens it again", row.helpOpen, { key: row.settingKey });
            root.saveShot(row, "help-open-row", () => root.next());
        });
    }

    // -------------------------------------------------------------- requires

    function requiresStep() {
        root.openPage("windows", ready => {
            const rows = root.findAll(root.win.contentItem, "row:", []).filter(r => r.visible && r.requires);
            const row = rows[0];
            const chip = row ? root.findItem(row, "chip:requires") : null;
            if (!root.check("requires: a row disabled by another setting shows the chip", ready && chip?.visible, {
                key: row?.settingKey ?? null, text: row?.requires?.text ?? null })) {
                root.next();
                return;
            }
            const targetKey = row.requires.key;
            const target = root.rowFor(targetKey);
            root.check("requires: the chip text names the setting", row.requires.text.indexOf(Translation.tr(SettingsRegistry.entry(targetKey).label)) >= 0, { text: row.requires.text });
            root.check("requires: the chip is a keyboard link", chip.interactive && (chip.focusPolicy & Qt.TabFocus) && chip.Accessible.role === Accessible.Link, { key: row.settingKey });
            const lockLine = root.findItem(row, "lockReason");
            root.check("requires: no lock line repeats the chip", row.disabledReason === row.requires.text && !!lockLine && !lockLine.visible, {
                reason: row.disabledReason, lockLine: lockLine ? lockLine.visible : null });
            const dependent = row.parent?.parent;
            root.check("requires: a row that depends on its section is indented", targetKey && SettingsRegistry.entry(targetKey).section === row.entry.section ? (dependent?.dependent === true && row.parent.anchors.leftMargin > 0) : true, { key: row.settingKey });
            root.saveShot(row, "requires-row", () => {
                // Scroll away so the jump must move the page.
                row.page.contentY = 0;
                chip.forceActiveFocus(Qt.TabFocusReason);
                root.key(Qt.Key_Return);
                root.waitFor(() => target?.highlighted === true, 3000, ok => {
                    root.check("requires: Enter on the chip reveals and highlights the target", ok, { target: targetKey });
                    root.crossPageStep();
                });
            });
        });
    }

    // A "Requires …" chip whose target lives on another page reveals it there
    // (SettingsRow.revealDependency -> SettingsSession -> settings.qml reveal).
    // No registry entry depends on another page yet, so this step points
    // notifications.timeout (notifications page, not created yet: rows read
    // enabledWhen and the page groups dependents when they are created; the
    // row has no capability, so it shows in the sandbox) at an animations
    // setting the stub leaves on, presses Space on the real chip, then
    // restores the entry.
    readonly property string crossPagePage: "notifications"
    readonly property string crossPageKey: "notifications.timeout"
    readonly property string crossPageTarget: "hyprland.animations.enabled"

    function crossPageStep() {
        const entry = SettingsRegistry.entry(root.crossPageKey);
        if (!root.check("requires: cross-page fixture applies", !root.rowOn(root.crossPagePage, root.crossPageKey) && entry.enabledWhen === undefined
                && SettingsRegistry.entry(root.crossPageTarget).section !== undefined)) {
            root.next();
            return;
        }
        entry.enabledWhen = { key: root.crossPageTarget, equals: false };
        const finish = () => {
            delete entry.enabledWhen;
            root.next();
        };
        root.openPage(root.crossPagePage, () => {
            const chipOf = () => {
                const row = root.rowOn(root.crossPagePage, root.crossPageKey);
                return row ? root.findItem(row, "chip:requires") : null;
            };
            root.waitFor(() => chipOf()?.visible === true, 3000, ready => {
                const row = root.rowOn(root.crossPagePage, root.crossPageKey);
                const chip = chipOf();
                if (!root.check("requires: a chip can point to another page", ready && row.requires?.key === root.crossPageTarget, {
                    key: root.crossPageKey, row: row ? row.visible : null, chip: chip ? chip.visible : null, text: row?.requires?.text ?? null })) {
                    finish();
                    return;
                }
                root.pressCrossPageChip(chip, finish);
            });
        });
    }

    function pressCrossPageChip(chip, finish) {
        {
            chip.forceActiveFocus(Qt.TabFocusReason);
            root.key(Qt.Key_Space);
            root.waitFor(() => root.currentPageId() === "animations" && root.rowOn("animations", root.crossPageTarget)?.highlighted === true, 4000, ok => {
                root.check("requires: a link to another page opens it and highlights the row", ok, { page: root.currentPageId() });
                finish();
            });
        }
    }

    // ----------------------------------------------------------------- chips

    function chipsStep() {
        const pages = ["windows", "animations", "input", "displays", "power", "bar", "advanced"];
        const run = index => {
            if (index >= pages.length) {
                root.next();
                return;
            }
            root.openPage(pages[index], () => {
                const rows = root.findAll(root.win.contentItem, "row:", []).filter(r => r.visible && r.chips !== undefined);
                const tooMany = rows.filter(r => r.chips.length > 2 || root.findAll(r, "chip:", []).filter(c => c.visible).length > 2).map(r => r.settingKey);
                root.check("chips: at most 2 per row", tooMany.length === 0, { page: pages[index], rows: rows.length, tooMany: tooMany });
                run(index + 1);
            });
        };
        run(0);
    }

    // ---------------------------------------------------------- backend-down

    function backendDownStep() {
        root.openPage("windows", ready => {
            const page = root.rowFor("hyprland.general.gaps_in")?.page ?? null;
            const sections = root.findAll(page, "section:", []).filter(s => s.visible);
            let checked = 0;
            for (const section of sections) {
                const rows = root.findAll(section, "row:", []).filter(r => r.visible && r.writable !== undefined);
                const down = rows.filter(r => r.writable && !SettingsStore.isAvailable(r.settingKey));
                if (down.length === 0)
                    continue;
                checked++;
                const banner = root.findItem(section, "sectionBanner:" + section.sectionId);
                const banners = root.findAll(section, "sectionBanner:", []).filter(b => b.visible).length;
                root.check("backend-down: one banner per section", banner?.visible && banners === 1 && banner.text === Translation.tr(SettingsStore.unavailableReason(down[0].settingKey)), {
                    section: section.sectionId, banner: banner?.text ?? null });
                const fake = down.filter(r => !root.findItem(r, "valuePlaceholder")?.visible);
                root.check("backend-down: rows show — instead of a value", fake.length === 0, { section: section.sectionId, fake: fake.map(r => r.settingKey) });
                const repeated = down.filter(r => r.reasonInBanner !== true);
                root.check("backend-down: rows do not repeat the banner's reason", repeated.length === 0, { section: section.sectionId, repeated: repeated.map(r => r.settingKey) });
            }
            root.check("backend-down: Hyprland sections checked", ready && checked >= 3, { sections: checked });
            root.saveShot(page, "backend-down-windows", () => root.next());
        });
    }

    // ------------------------------------------------------------------ flow

    function next() {
        if (root.stepIndex >= root.steps.length) {
            root.report({ type: "done", failures: root.failures });
            Qt.quit();
            return;
        }
        const step = root.steps[root.stepIndex++];
        root.report({ type: "visit", size: `${root.win.width}x${root.win.height}`, name: step });
        if (step === "option-texts")
            root.optionTextsStep();
        else if (step === "help-search")
            root.helpSearchStep();
        else if (step === "help-keys")
            root.helpKeysStep();
        else if (step === "requires")
            root.requiresStep();
        else if (step === "chips")
            root.chipsStep();
        else
            root.backendDownStep();
    }

    function start() {
        root.keys = Qt.createQmlObject("import QtQuick; import QtTest; TestCase { when: false }", root.win.contentItem, "harnessKeys");
        const hyprland = SettingsStore.isAvailable("hyprland.general.gaps_in");
        root.steps = hyprland ? ["option-texts", "help-search", "help-keys", "requires", "chips"] : ["backend-down"];
        root.report({ type: "start", mode: hyprland ? "hyprland" : "backend-down", steps: root.steps });
        root.next();
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

    Timer {
        interval: 100
        repeat: true
        running: true
        property int waited: 0
        onTriggered: {
            waited += interval;
            if (Config.ready && root.win?.pageReady) {
                stop();
                startDelay.start();
            } else if (waited > 20000) {
                stop();
                root.fail("settings never became ready");
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
