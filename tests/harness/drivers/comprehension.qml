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
//                no lock line and no second sentence of the accessible
//                description repeats it, and Space on a chip whose target
//                is on another page (a test enabledWhen) opens that page;
//   chips        no row of the visited pages shows more than 2 chips;
//   status-note  with Game Mode on (its overrides file in the sandbox), a
//                row it pauses shows the backend's status note as an italic,
//                translated line, gone again when Game Mode ends;
//   navigation   the modified count of a page is hidden at 0 with its width
//                reserved (same width on every item), shows the count above
//                0 and says «Ajustes modificados: N» to screen readers; no
//                page title is elided at 1100 and 1600 px wide (nor at
//                760 px with the list expanded), and the list keeps its
//                width when a count appears or another page is selected.
// Without Hyprland:
//   backend-down on the Windows, Input and Animations pages every writable
//                row whose backend is down shows "—" and no live control
//                (Input covers list and text rows); a section where all of
//                them share the reason shows it once in a banner (on Windows
//                every Hyprland section does).
// Results are "[harness:report]" lines; any failure is a "fatal" event.
import QtQuick
import Quickshell
import Quickshell.Io
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

    // The target row is looked up on its own page: a key aliased on the Quick
    // page also has a (hidden) row there with the same objectName.
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
            const row = root.rowOn(target.pageId, target.key);
            return root.currentPageId() === target.pageId && row?.visible && row.highlighted && row.helpOpen;
        }, 4000, ok => {
            const row = root.rowOn(target.pageId, target.key);
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
            root.checkSaidOnce(row);
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

    // Screen readers hear the "Requires …" sentence once: the chip says it,
    // the disabled reason (the same sentence) is left out.
    function checkSaidOnce(row) {
        const said = row.requires.text.replace(/[.\s]+$/, "");
        const description = row.Accessible.description;
        root.check("requires: the accessible description says it once", description.split(said).length - 1 === 1, {
            key: row.settingKey, description: description });
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
                root.checkSaidOnce(row);
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

    // Pages whose writable rows depend on Hyprland: Windows (switches and
    // sliders, every section shares the reason), Input (also list and text
    // rows: layouts, variants, XKB options) and Animations.
    readonly property var downPages: [
        { id: "windows", minSections: 3, bannerEverywhere: true, types: [] },
        { id: "input", minSections: 1, bannerEverywhere: false, types: ["list", "string"] },
        { id: "animations", minSections: 1, bannerEverywhere: false, types: [] }
    ]

    function backendDownStep() {
        const run = index => {
            if (index >= root.downPages.length) {
                root.next();
                return;
            }
            const spec = root.downPages[index];
            root.openPage(spec.id, ready => {
                const page = root.findAll(root.win.contentItem, "row:", []).find(r => r.visible && r.page?.pageId === spec.id)?.page ?? null;
                root.checkDownPage(spec, ready, page);
                root.saveShot(page, `backend-down-${spec.id}`, () => run(index + 1));
            });
        };
        run(0);
    }

    function checkDownPage(spec, ready, page) {
        const sections = root.findAll(page, "section:", []).filter(s => s.visible);
        let checked = 0;
        let allDown = [];
        for (const section of sections) {
            const rows = root.findAll(section, "row:", []).filter(r => r.visible && r.writable !== undefined);
            const down = rows.filter(r => r.writable && !SettingsStore.isAvailable(r.settingKey));
            if (down.length === 0)
                continue;
            checked++;
            allDown = allDown.concat(down);
            const where = { page: spec.id, section: section.sectionId };
            const reason = page.sectionBannerReason(section.sectionId);
            const banner = root.findItem(section, "sectionBanner:" + section.sectionId);
            const banners = root.findAll(section, "sectionBanner:", []).filter(b => b.visible).length;
            if (spec.bannerEverywhere || reason.length > 0) {
                root.check("backend-down: one banner per section", banner?.visible && banners === 1 && banner.text === Translation.tr(SettingsStore.unavailableReason(down[0].settingKey)), Object.assign({
                    banner: banner?.text ?? null }, where));
                const repeated = down.filter(r => r.reasonInBanner !== true);
                root.check("backend-down: rows do not repeat the banner's reason", repeated.length === 0, Object.assign({ repeated: repeated.map(r => r.settingKey) }, where));
            } else {
                root.check("backend-down: no banner without a shared reason", banners === 0, Object.assign({ banners: banners }, where));
            }
            const fake = down.filter(r => !root.findItem(r, "valuePlaceholder")?.visible || root.findItem(r, "rowControl")?.visible !== false);
            root.check("backend-down: rows show — instead of a value", fake.length === 0, Object.assign({ fake: fake.map(r => r.settingKey) }, where));
        }
        const types = allDown.map(r => r.entry.type);
        root.check("backend-down: Hyprland sections checked", ready && checked >= spec.minSections && spec.types.every(t => types.includes(t)), {
            page: spec.id, sections: checked, rows: allDown.map(r => `${r.settingKey}:${r.entry.type}`) });
    }

    // ----------------------------------------------------------- status-note

    // Game Mode is on while its overrides file sets animations off; the
    // Hyprland backend then pauses the options it overrides and says so with
    // statusNote(entry) (contracts phase A §3).
    readonly property string overridesFile: `${Quickshell.env("XDG_CONFIG_HOME")}/hypr/hyprland/shellOverrides/main.lua`
    readonly property string configurator: Quickshell.shellPath("scripts/hyprland/hyprconfigurator.py")
    readonly property string pausedKey: "hyprland.general.gaps_in"

    function run(argv, done) {
        const proc = procComponent.createObject(root, { command: argv });
        proc.exited.connect(code => {
            proc.destroy();
            done(code);
        });
        proc.running = true;
    }

    // Game Mode's toggle makes Hyprland reload, and the backend re-reads the
    // overrides file on "configreloaded" (its watch cannot see the file being
    // created). The stub has no event socket, so the driver delivers the
    // event to the store's Hyprland backend itself.
    function hyprlandBackend() {
        return SettingsStore.backends?.hyprland ?? null;
    }

    function configReloaded() {
        root.hyprlandBackend()?.hyprlandEvents.onRawEvent({ name: "configreloaded" });
    }

    function statusNoteStep() {
        root.check("status-note: the Hyprland backend is reachable", root.hyprlandBackend() !== null, {});
        const expected = "Pausado por el Modo Juego";
        root.check("status-note: the note is translated", Translation.tr("Paused by Game Mode") === expected, { tr: Translation.tr("Paused by Game Mode") });
        root.openPage("windows", () => {
            const before = root.rowOn("windows", root.pausedKey);
            const line = before ? root.findItem(before, "statusNote") : null;
            root.check("status-note: no line without a note", !!line && !line.visible && before.statusNote === "", { key: root.pausedKey });
            const args = ["--set", "animations:enabled", "0", "--set", "general:gaps_in", "0"];
            root.run(["mkdir", "-p", root.overridesFile.replace(/\/[^/]*$/, "")], () => root.run(["python3", root.configurator, "--file", root.overridesFile].concat(args), code => {
                root.configReloaded();
                root.waitFor(() => root.rowOn("windows", root.pausedKey)?.statusNote.length > 0, 8000, ok => {
                    const row = root.rowOn("windows", root.pausedKey);
                    const note = row ? root.findItem(row, "statusNote") : null;
                    const text = note ? root.findItem(note, "statusNoteText") : null;
                    root.check("status-note: a paused row shows the translated note in italics", code === 0 && ok && note?.visible && text?.visible
                        && text.text === expected && text.font.italic === true, {
                        code: code, note: row?.statusNote ?? null, visible: note ? note.visible : null, italic: text ? text.font.italic : null });
                    root.check("status-note: the accessible description includes it", !!row && row.Accessible.description.indexOf(expected) >= 0, {
                        description: row?.Accessible.description ?? null });
                    root.saveShot(row, "status-note-row", () => {
                        const reset = ["--reset", "animations:enabled", "--reset", "general:gaps_in"];
                        root.run(["python3", root.configurator, "--file", root.overridesFile].concat(reset), () => {
                            root.configReloaded();
                            root.waitFor(() => root.rowOn("windows", root.pausedKey)?.statusNote === "", 8000, gone => {
                                root.check("status-note: the line goes away with Game Mode", gone && !root.findItem(root.rowOn("windows", root.pausedKey), "statusNote").visible, {});
                                root.next();
                            });
                        });
                    });
                });
            }));
        });
    }

    // ------------------------------------------------------------ navigation

    function navItems() {
        const nav = root.findItem(root.win.contentItem, "settingsNavigation");
        return root.findAll(nav, "nav:", []).filter(i => i.visible);
    }

    function titleStates() {
        return root.navItems().map(i => ({ page: i.page.id, title: i.title, elided: root.findItem(i, "navTitle")?.truncated ?? null }));
    }

    function checkTitles(size) {
        const states = root.titleStates();
        const nav = root.findItem(root.win.contentItem, "settingsNavigation");
        root.report({ type: "nav-titles", size: size, navWidth: nav.width, titles: states });
        root.check("navigation: no page title is elided", states.length > 0 && states.every(t => t.elided === false), {
            size: size, elided: states.filter(t => t.elided !== false).map(t => t.title) });
    }

    function navigationStep() {
        const nav = root.findItem(root.win.contentItem, "settingsNavigation");
        const items = root.navItems();
        const slot = item => root.findItem(item, "modifiedCount");
        const widths = items.map(i => slot(i)?.width ?? -1);
        root.check("navigation: the count keeps the same width on every item", items.length > 0 && widths.every(w => w > 0 && w === widths[0]), {
            widths: widths });
        const zero = items.filter(i => i.modifiedCount === 0);
        const some = items.filter(i => i.modifiedCount > 0);
        root.check("navigation: pages with and without changes", zero.length > 0 && some.length > 0, {
            zero: zero.map(i => i.page.id), some: some.map(i => i.page.id) });
        root.check("navigation: hidden at 0", zero.every(i => slot(i).opacity === 0 && slot(i).text === "" && i.Accessible.description === ""), {
            pages: zero.filter(i => slot(i).opacity !== 0 || i.Accessible.description !== "").map(i => i.page.id) });
        const described = i => Translation.tr("Changed settings: %1").arg(i.modifiedCount);
        root.check("navigation: the count shows above 0 and is described", some.every(i => slot(i).opacity === 1 && slot(i).visible
            && slot(i).text === String(i.modifiedCount) && i.Accessible.description === described(i))
            && Translation.tr("Changed settings: %1") === "Ajustes modificados: %1", {
            pages: some.map(i => ({ page: i.page.id, count: i.modifiedCount, text: slot(i).text, description: i.Accessible.description })) });
        root.checkTitles(`${root.win.width}x${root.win.height}`);
        root.saveShot(nav, "navigation-1100", () => root.countProbeStep(nav));
    }

    // A count appearing must not move the list: the list is sized from the
    // items' implicit widths, so an item for the longest title has the same
    // implicit width with a count of 0 and above 0, selected or not. Two
    // invisible probe items stand in for one page whose count changes (the
    // strict harness forbids the writes a real change would need).
    function countProbeStep(nav) {
        const items = root.navItems();
        const zero = items.find(i => i.modifiedCount === 0);
        const some = items.find(i => i.modifiedCount > 0);
        const longest = items.reduce((a, b) => b.implicitWidth > a.implicitWidth ? b : a, items[0]);
        const component = Qt.createComponent(Quickshell.shellPath("modules/settings/components/SettingsNavigationItem.qml"));
        const probe = (page, selected) => component.createObject(root.win.contentItem, {
            opacity: 0, z: -1, expanded: true, selected: selected,
            page: { id: page.id, title: longest.page.title, icon: longest.page.icon }
        });
        const probes = zero && some && component.status === Component.Ready ? [probe(zero.page, false), probe(some.page, false), probe(some.page, true)] : [];
        const widths = probes.map(p => p.implicitWidth);
        root.check("navigation: a count appearing or a selection keeps the item's width", probes.length === 3
            && probes[0].modifiedCount === 0 && probes[1].modifiedCount > 0 && widths.every(w => w > 0 && w === widths[0]), {
            title: longest?.title ?? null, widths: widths, error: component.errorString() });
        root.check("navigation: the list is as wide as its longest title needs", nav.expandedWidth === Math.min(SettingsMetrics.navMaxExpandedWidth,
            Math.max(SettingsMetrics.navExpandedWidth, ...items.map(i => i.implicitWidth))) && nav.width === nav.expandedWidth, {
            width: nav.width, expandedWidth: nav.expandedWidth, longest: longest?.implicitWidth ?? null });
        for (const p of probes)
            p.destroy();
        root.otherSizesStep(nav);
    }

    // The window is resized in place; the list follows its width once the
    // layout has run (nav.windowWidth), then settles after its width
    // animation.
    function otherSizesStep(nav) {
        root.win.width = 1600;
        root.win.height = 900;
        root.waitFor(() => nav.windowWidth === 1600 && nav.width === nav.expandedWidth, 3000, wide => {
            root.check("navigation: the window grew to 1600 px", wide, { windowWidth: nav.windowWidth });
            root.checkTitles("1600x900");
            root.win.width = 760;
            root.win.height = 720;
            root.waitFor(() => nav.windowWidth === 760 && !nav.expanded, 3000, narrow => {
                root.check("navigation: the list collapses at 760 px", narrow, { windowWidth: nav.windowWidth });
                nav.userExpanded = true;
                root.waitFor(() => nav.expanded && nav.width === nav.expandedWidth, 3000, () => {
                    root.checkTitles("760x720 expanded");
                    root.saveShot(nav.parent, "navigation-760-expanded", () => {
                        nav.userExpanded = null;
                        root.win.width = 1100;
                        root.win.height = 760;
                        root.waitFor(() => nav.windowWidth === 1100 && nav.width === nav.expandedWidth, 3000, () => root.next());
                    });
                });
            });
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
        else if (step === "status-note")
            root.statusNoteStep();
        else if (step === "navigation")
            root.navigationStep();
        else
            root.backendDownStep();
    }

    function start() {
        root.keys = Qt.createQmlObject("import QtQuick; import QtTest; TestCase { when: false }", root.win.contentItem, "harnessKeys");
        const hyprland = SettingsStore.isAvailable("hyprland.general.gaps_in");
        root.steps = hyprland ? ["option-texts", "help-search", "help-keys", "requires", "chips", "status-note", "navigation"] : ["backend-down"];
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
        id: procComponent
        Process {}
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
