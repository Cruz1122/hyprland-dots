import QtQuick
import QtTest
import "../../config/quickshell/ii/modules/settings/core/SettingsLogic.js" as Logic

TestCase {
    name: "SettingsLogic"

    function test_deep_get_set_equal() {
        const obj = { a: { b: { c: 1 } }, list: ["x"] };
        compare(Logic.getPath(obj, "a.b.c"), 1);
        compare(Logic.getPath(obj, "a.x.c"), undefined);
        verify(Logic.setPath(obj, "a.b.c", 2));
        compare(obj.a.b.c, 2);
        verify(!Logic.setPath(obj, "a.b.missing", 3), "never creates properties");
        verify(!Logic.setPath(obj, "a.x.c", 3));
        verify(Logic.deepEqual([1, { a: [2] }], [1, { a: [2] }]));
        verify(!Logic.deepEqual([1, 2], [2, 1]));
        verify(!Logic.deepEqual({ a: 1 }, { a: 1, b: 2 }));
        verify(!Logic.deepEqual(0, false));
        verify(!Logic.deepEqual("1", 1));
    }

    function test_coerce_numbers() {
        const intEntry = { type: "int", min: 0, max: 10 };
        compare(Logic.coerce(intEntry, 4.6).value, 5);
        compare(Logic.coerce(intEntry, "7").value, 7);
        compare(Logic.coerce(intEntry, 99).value, 10);
        compare(Logic.coerce(intEntry, -3).value, 0);
        verify(!Logic.coerce(intEntry, "abc").ok);
        verify(!Logic.coerce(intEntry, "").ok);
        verify(!Logic.coerce(intEntry, NaN).ok);
        verify(!Logic.coerce(intEntry, true).ok);
        const realEntry = { type: "real", min: 0, max: 1, decimals: 2 };
        compare(Logic.coerce(realEntry, 0.456).value, 0.46);
        compare(Logic.coerce(realEntry, 3).value, 1);
    }

    function test_coerce_enum_bool_strings_lists() {
        const e = { type: "enum", options: [{ value: "a" }, { value: 2 }] };
        compare(Logic.coerce(e, "a").value, "a");
        compare(Logic.coerce(e, 2).value, 2);
        verify(!Logic.coerce(e, "2").ok, "membership is type-exact");
        verify(Logic.coerce({ type: "bool" }, false).ok);
        verify(!Logic.coerce({ type: "bool" }, "true").ok);
        compare(Logic.coerce({ type: "string" }, 10001).value, "10001", "numbers stay text");
        const strict = { type: "string", validate: { regex: "^[a-z]+$", maxLength: 4, nonEmpty: true } };
        verify(!Logic.coerce(strict, "").ok);
        verify(!Logic.coerce(strict, "abcde").ok);
        verify(!Logic.coerce(strict, "AB").ok);
        verify(Logic.coerce(strict, "ab").ok);
        verify(Logic.coerce({ type: "color" }, "").ok);
        verify(Logic.coerce({ type: "color" }, "#a1b2c3").ok);
        verify(!Logic.coerce({ type: "color" }, "red").ok);
        verify(Logic.coerce({ type: "time" }, "07:30").ok);
        verify(!Logic.coerce({ type: "time" }, "24:00").ok);
        compare(Logic.coerce({ type: "list" }, ["a", 2]).value, ["a", "2"]);
        verify(!Logic.coerce({ type: "list" }, "a").ok);
        verify(!Logic.coerce({ type: "list" }, [{}]).ok);
        verify(!Logic.coerce({ type: "list", validate: { nonEmpty: true } }, ["a", " "]).ok);
        verify(!Logic.coerce({ type: "action" }, 1).ok);
    }

    function test_unique_conflict() {
        const e = { key: "a" };
        compare(Logic.uniqueConflict(e, "x", [{ key: "b", value: "x" }]), "b");
        compare(Logic.uniqueConflict(e, "x", [{ key: "a", value: "x" }, { key: "b", value: "y" }]), "");
    }

    function test_conditions() {
        const values = { on: true, n: 2, s: "x" };
        const valueOf = k => values[k];
        const caps = c => c === "battery";
        verify(Logic.evalCondition(undefined, valueOf, caps));
        verify(Logic.evalCondition({ key: "on", equals: true }, valueOf, caps));
        verify(!Logic.evalCondition({ key: "on", notEquals: true }, valueOf, caps));
        verify(Logic.evalCondition({ key: "n", "in": [1, 2] }, valueOf, caps));
        verify(Logic.evalCondition({ capability: "battery" }, valueOf, caps));
        verify(!Logic.evalCondition({ capability: "touchpad" }, valueOf, caps));
        verify(Logic.evalCondition({ all: [{ key: "on", equals: true }, { not: { key: "s", equals: "y" } }] }, valueOf, caps));
        verify(Logic.evalCondition({ any: [{ key: "on", equals: false }, { key: "n", equals: 2 }] }, valueOf, caps));
        const blocking = Logic.blockingCondition({ all: [{ key: "on", equals: true }, { capability: "touchpad" }] }, valueOf, caps);
        compare(blocking.capability, "touchpad");
        compare(Logic.blockingCondition({ key: "on", equals: true }, valueOf, caps), null);
    }

    function registry() {
        const pages = { groups: [{ id: "g", title: "G", pages: ["one", "two"] }], footer: ["three"] };
        const docs = {
            one: {
                id: "one", title: "Appearance", icon: "palette", description: "Looks.",
                sections: [{ id: "s", title: "Dimming" }],
                entries: [
                    { key: "a.dim", section: "s", label: "Dim inactive windows", description: "Lower the brightness.", keywords: ["atenuación"], backend: "config", type: "bool" },
                    { key: "a.bright", section: "s", label: "Brightness", description: "How dim the window gets.", backend: "config", type: "real" },
                    { key: "ai.tool", section: "s", label: "Retired", backend: "config", type: "string" },
                    { key: "a.bad", section: "nope", label: "Bad", backend: "config", type: "bool" }
                ]
            },
            two: {
                id: "two", title: "Quick", icon: "bolt",
                sections: [{ id: "q", title: "Quick" }],
                entries: [{ ref: "a.dim", section: "q" }, { ref: "a.dim", section: "q" }, { ref: "missing", section: "q" }]
            },
            three: null
        };
        return Logic.buildRegistry(pages, docs, { retired: ["ai"], managedElsewhere: [] });
    }

    // Regression: device rows forced translate:false on every choice, so
    // backend labels such as idle timeouts stayed in English.
    function test_device_choices_translate_only_marked_labels() {
        const mapped = Logic.deviceChoices([
            { value: "alsa_output.pci", label: "Speakers", icon: "audio-card" },
            { value: 0, label: "Never", translate: true },
            { value: "firefox.desktop", label: "Firefox", translate: false }
        ]);
        compare(mapped.map(o => o.translate), [false, true, false]);
        compare(mapped.map(o => o.icon), ["", "", ""]);
        compare(mapped[1].value, 0);
        compare(mapped[1].label, "Never");
        compare(Logic.deviceChoices(undefined).length, 0);
    }

    // Regression: the wallpaper card loaded a video wallpaper as an image, so
    // the preview stayed empty and Qt warned "Cannot open".
    function test_wallpaper_preview_uses_the_thumbnail_of_videos() {
        compare(Logic.wallpaperPreview("/w/a.png", "/t/old.jpg"), "/w/a.png");
        compare(Logic.wallpaperPreview("/w/a.mp4", "/t/a.mp4.jpg"), "/t/a.mp4.jpg");
        compare(Logic.wallpaperPreview("/w/a.webm", undefined), "", "no thumbnail yet: placeholder");
        compare(Logic.wallpaperPreview("", "/t/a.jpg"), "");
        compare(Logic.wallpaperPreview(undefined, undefined), "");
        verify(Logic.wallpaperIsVideo("/w/clip.mkv"));
        verify(!Logic.wallpaperIsVideo("/w/clip.mp4.png"));
    }

    function test_capability_reasons() {
        compare(Logic.capabilityReason("satty"), "Requires satty, which is not installed");
        compare(Logic.capabilityReason("touchpad"), "No touchpad detected");
        compare(Logic.capabilityReason("ipc:regionRecord"), "The main shell is not running or is out of date");
        compare(Logic.capabilityReason("unknown"), "Not supported on this system");
        compare(Logic.capabilityReason("constructor"), "Not supported on this system");
    }

    // applies/cost typos must surface in loadErrors instead of rendering a
    // row with an unknown chip.
    function test_registry_validates_guidance_fields() {
        const pages = { groups: [{ id: "g", title: "G", pages: ["one"] }], footer: [] };
        const entry = (key, extra) => Object.assign({ key: key, section: "s", label: key, backend: "animation", type: "custom", widget: "animation" }, extra);
        const docs = {
            one: {
                id: "one", title: "One", icon: "animation",
                sections: [{ id: "s", title: "S" }],
                entries: [
                    entry("animation.ok", { applies: "newWindows", cost: "gpu", help: "Why.", minLabel: "Fast", maxLabel: "Slow" }),
                    entry("animation.plain", {}),
                    entry("animation.badApplies", { applies: "later" }),
                    entry("animation.badCost", { cost: "cpu" }),
                    entry("animation.badWidget", { widget: "sparkle" })
                ]
            }
        };
        const model = Logic.buildRegistry(pages, docs, { retired: [], managedElsewhere: [] });
        compare(Object.keys(model.entryByKey).sort(), ["animation.ok", "animation.plain"]);
        compare(model.errors.length, 3, JSON.stringify(model.errors));
        verify(model.errors.some(e => e.indexOf("unknown applies \"later\"") >= 0), JSON.stringify(model.errors));
        verify(model.errors.some(e => e.indexOf("unknown cost \"cpu\"") >= 0), JSON.stringify(model.errors));
        const ok = model.entryByKey["animation.ok"];
        compare([ok.applies, ok.cost, ok.help, ok.minLabel, ok.maxLabel], ["newWindows", "gpu", "Why.", "Fast", "Slow"]);
        const plain = model.entryByKey["animation.plain"];
        compare([plain.applies, plain.cost, plain.help, plain.minLabel, plain.maxLabel], ["", "", "", "", ""]);
        compare(Logic.capabilityReason("animationsLoaded"), "Hyprland does not load the animation settings yet: update the dotfiles");
        compare(Logic.capabilityReason("vrr"), "No connected display supports variable refresh rate (FreeSync/G-Sync)");
    }

    function test_registry_skips_broken_parts() {
        const model = registry();
        compare(model.pages.map(p => p.id), ["one", "two", "three"]);
        compare(model.footerPages.length, 1);
        verify(model.pageById.three.broken);
        verify(model.entryByKey["a.dim"]);
        verify(!model.entryByKey["ai.tool"], "retired paths are rejected");
        verify(!model.entryByKey["a.bad"], "unknown section is rejected");
        compare(model.entryByKey["a.dim"].widget, "switch");
        compare(model.entryByKey["a.bright"].widget, "slider");
        verify(model.errors.length >= 5, JSON.stringify(model.errors));
    }

    function test_aliases_resolve_to_canonical_entries() {
        const model = registry();
        const quick = model.pageById.two.entries;
        compare(quick.length, 1, "duplicate and unknown refs are dropped");
        compare(quick[0].key, "a.dim");
        compare(quick[0].section, "q");
        compare(quick[0].aliasOf, "a.dim");
        compare(quick[0].homePageId, "one");
        compare(model.entryByKey["a.dim"].section, "s", "canonical entry untouched");
    }

    function test_search_folds_diacritics_and_ranks() {
        const model = registry();
        const tr = t => t === "Dim inactive windows" ? "Atenuar ventanas inactivas" : t;
        const docs = Logic.searchDocuments(model, tr);
        const accented = Logic.search(docs, "atenuación", 10);
        const plain = Logic.search(docs, "ATENUACION", 10);
        compare(JSON.stringify(accented), JSON.stringify(plain));
        compare(accented[0].key, "a.dim");
        verify(accented.every(r => r.pageId === "one"), "aliases never appear");
        const dim = Logic.search(docs, "dim", 10);
        compare(dim[0].key, "a.dim", "label prefix first, settings before sections on ties");
        compare(dim[1].kind, "section");
        compare(dim[dim.length - 1].key, "a.bright", "description match last");
        compare(Logic.search(docs, "atenuar", 10)[0].key, "a.dim", "translated label");
        compare(Logic.search(docs, "dimming", 10)[0].kind, "section");
        compare(Logic.search(docs, "dim windows", 10)[0].key, "a.dim");
        compare(Logic.search(docs, "dim zzz", 10).length, 0, "every word must match");
        compare(Logic.search(docs, "  ", 10).length, 0);
        compare(Logic.search(docs, "appearance", 10)[0].kind, "page");
    }

    // Search also reads help texts and option labels/descriptions, English
    // and translated, accent-insensitive, and says which field matched.
    function test_search_matches_help_and_options() {
        const model = Logic.buildRegistry(
            { groups: [{ id: "g", title: "G", pages: ["w"] }], footer: [] },
            { w: { id: "w", title: "Windows", sections: [{ id: "s", title: "Spacing" }], entries: [
                { key: "w.gap", section: "s", label: "Gap", backend: "hyprland", type: "int",
                  help: "Inactive windows keep their dimming." },
                { key: "w.style", section: "s", label: "Style", backend: "hyprland", type: "enum",
                  options: [{ value: "popin", label: "Pop in", description: "The window grows from its center." },
                            { value: "slide", label: "Slide" }] }
            ] } },
            { retired: [], managedElsewhere: [] });
        const es = {
            "Inactive windows keep their dimming.": "Las ventanas inactivas conservan su atenuación.",
            "Pop in": "Emerger",
            "The window grows from its center.": "La ventana crece desde el centro."
        };
        const tr = t => es[t] ?? t;
        const docs = Logic.searchDocuments(model, tr);
        for (const q of ["atenuacion", "atenuación", "ATENUACIÓN", "dimming"]) {
            const r = Logic.search(docs, q, 10);
            compare(r.length, 1, q);
            compare(r[0].key, "w.gap", q);
            compare(r[0].fields, ["help"], q);
            verify(r[0].helpMatched, q);
        }
        const option = Logic.search(docs, "emerger", 10);
        compare(option[0].key, "w.style");
        compare(option[0].fields, ["option"]);
        verify(!option[0].helpMatched);
        compare(Logic.search(docs, "pop", 10)[0].key, "w.style", "English option label");
        compare(Logic.search(docs, "centro", 10)[0].key, "w.style", "translated option description");
        const label = Logic.search(docs, "gap", 10);
        compare(label[0].fields, ["label"]);
        verify(!label[0].helpMatched);
        const mixed = Logic.search(docs, "gap atenuacion", 10);
        compare(mixed[0].fields, ["label", "help"]);
        verify(mixed[0].helpMatched, "one word found only in the help opens it");
        verify(Logic.scoreToken(docs.find(d => d.key === "w.style"), "emerger") > Logic.scoreToken(docs.find(d => d.key === "w.gap"), "atenuacion"),
            "option labels rank above help text");
    }

    function test_chips_priority_and_limit() {
        const ids = chips => chips.map(c => c.id);
        compare(Logic.rowChips({ key: "a" }, null), []);
        compare(ids(Logic.rowChips({ key: "a", cost: "gpu" }, null)), ["gpu"]);
        compare(ids(Logic.rowChips({ key: "a", applies: "newWindows", cost: "gpu" }, null)), ["newWindows", "gpu"]);
        compare(ids(Logic.rowChips({ key: "a", applies: "onSave", cost: "battery" }, { key: "b", text: "Requires “B”" })),
            ["requires", "onSave"], "at most 2, the dependency first");
        compare(ids(Logic.rowChips({ key: "a", risky: true, cost: "gpu" }, null)), ["confirm", "gpu"], "risky entries ask for confirmation");
        compare(ids(Logic.rowChips({ key: "a", risky: true, applies: "nextStart" }, null)), ["nextStart"], "an explicit applies wins");
        compare(ids(Logic.rowChips({ key: "a", applies: "confirm", cost: "gpu" }, { key: "b", text: "Requires “B”" })), ["requires", "confirm"]);
        compare(ids(Logic.rowChips({ key: "a", applies: "bogus", cost: "bogus" }, null)), [], "unknown values never render");
        const req = Logic.rowChips({ key: "a" }, { key: "b", text: "Requires “B”" })[0];
        compare(req.kind, "requires");
        compare(req.target, "b");
        compare(req.label, "Requires “B”");
        compare(Logic.rowChips({ key: "a", applies: "nextLogin" }, null)[0].label, "At next login");
        for (const id in Logic.APPLIES_LABELS)
            verify(Logic.CHIP_RANK[id] !== undefined, id);
        for (const id in Logic.COST_LABELS)
            verify(Logic.CHIP_RANK[id] !== undefined, id);
    }

    function test_dependency_wording() {
        const tr = t => t;
        const flag = { key: "f", label: "Blur", type: "bool" };
        const style = { key: "s", label: "Clock style", type: "enum",
            options: [{ value: "cookie", label: "Cookie" }, { value: "digital", label: "Digital" }, { value: "numbers", label: "Numbers" }] };
        compare(Logic.dependencyText({ key: "f", equals: true }, flag, tr), "Requires “Blur”");
        compare(Logic.dependencyText({ key: "f" }, flag, tr), "Requires “Blur”", "truthy leaf");
        compare(Logic.dependencyText({ key: "f", equals: false }, flag, tr), "Requires “Blur” off");
        compare(Logic.dependencyText({ key: "f", notEquals: true }, flag, tr), "Requires “Blur” off");
        compare(Logic.dependencyText({ key: "f", notEquals: false }, flag, tr), "Requires “Blur”");
        compare(Logic.dependencyText({ not: { key: "f", equals: true } }, flag, tr), "Requires “Blur” off");
        compare(Logic.dependencyText({ not: { key: "f" } }, flag, tr), "Requires “Blur” off");
        compare(Logic.dependencyText({ key: "s", equals: "cookie" }, style, tr), "Requires “Clock style”: Cookie");
        compare(Logic.dependencyText({ key: "s", in: ["cookie"] }, style, tr), "Requires “Clock style”: Cookie");
        compare(Logic.dependencyText({ key: "s", in: ["cookie", "digital"] }, style, tr), "Requires “Clock style”: Cookie or Digital");
        compare(Logic.dependencyText({ key: "s", in: ["cookie", "digital", "numbers"] }, style, tr), "Requires “Clock style”: Cookie, Digital or Numbers");
        compare(Logic.dependencyText({ key: "s", notEquals: "numbers" }, style, tr), "Requires “Clock style” not set to Numbers");
        compare(Logic.dependencyText({ not: { key: "s", equals: "numbers" } }, style, tr), "Requires “Clock style” not set to Numbers");
        compare(Logic.dependencyText({ key: "x", equals: 1 }, null, tr), "Requires “x”: 1", "unknown target falls back to the key");
        compare(Logic.dependencyText({ capability: "touchpad" }, null, tr), "", "capabilities have their own reasons");
        const es = { "Requires “%1”: %2": "Requiere “%1”: %2", "Clock style": "Estilo del reloj", "Cookie": "Galleta", "Digital": "Digital", "%1 or %2": "%1 o %2" };
        compare(Logic.dependencyText({ key: "s", in: ["cookie", "digital"] }, style, t => es[t] ?? t), "Requiere “Estilo del reloj”: Galleta o Digital");
    }

    function test_value_formatting_and_reset_text() {
        const tr = t => t;
        const percent = { key: "o", type: "real", widget: "slider", unit: "%", uiScale: 100, decimals: 2 };
        compare(Logic.formatValue(percent, 0.5, tr), "50%", "percentages have no decimals");
        compare(Logic.displayDecimals(percent), 0);
        const px = { key: "g", type: "int", widget: "slider", unit: "px" };
        compare(Logic.formatValue(px, 4, tr), "4px");
        const power = { key: "r", type: "real", widget: "slider", decimals: 1 };
        compare(Logic.formatValue(power, 2, tr), "2.0");
        const minutes = { key: "m", type: "int", widget: "spin", unit: "min", uiScale: 1 / 60 };
        compare(Logic.formatValue(minutes, 1500, tr), "25 min");
        compare(Logic.formatValue({ key: "b", type: "bool" }, true, tr), "On");
        compare(Logic.formatValue({ key: "e", type: "enum", options: [{ value: 1, label: "One" }] }, 1, tr), "One");
        compare(Logic.formatValue({ key: "t", type: "string" }, "intl", tr), "“intl”");
        compare(Logic.formatValue({ key: "t", type: "string" }, "intl", t => t === "“%1”" ? "«%1»" : t), "«intl»", "quotes follow the language");
        compare(Logic.formatValue({ key: "t", type: "string" }, "", tr), "");
        compare(Logic.formatValue({ key: "l", type: "list" }, ["a"], tr), "");
        compare(Logic.resetText(px, 4, tr), "Reset to 4px");
        compare(Logic.resetText(percent, 1, tr), "Reset to 100%");
        compare(Logic.resetText(px, undefined, tr), "Reset", "unknown default: no value text");
        compare(Logic.resetText({ key: "l", type: "list" }, ["a"], tr), "Reset to default");
        compare(Logic.resetText({ key: "t", type: "string" }, "", tr), "Reset to default");
        compare(Logic.fmt("%1 of %2", "a", 3), "a of 3");
    }

    function test_section_banner_reason() {
        const down = { visible: true, writable: true, available: false, reason: "Hyprland is not running" };
        compare(Logic.sectionBannerReason([down, down]), "Hyprland is not running");
        compare(Logic.sectionBannerReason([down, { visible: true, writable: false, available: true, reason: "" }]), "Hyprland is not running",
            "read-only rows do not break the banner");
        compare(Logic.sectionBannerReason([down, { visible: false, writable: true, available: true, reason: "" }]), "Hyprland is not running",
            "hidden rows do not count");
        compare(Logic.sectionBannerReason([down, { visible: true, writable: true, available: true, reason: "" }]), "", "one row works");
        compare(Logic.sectionBannerReason([down, { visible: true, writable: true, available: false, reason: "Other" }]), "", "different reasons");
        compare(Logic.sectionBannerReason([]), "");
    }

    function test_section_dependencies() {
        const entry = { key: "b", enabledWhen: { all: [{ key: "a", equals: true }, { key: "elsewhere", equals: 1 }, { key: "a" }] } };
        compare(Logic.sectionDependencies(entry, ["a", "b"]), ["a"]);
        compare(Logic.sectionDependencies({ key: "a" }, ["a", "b"]), []);
        compare(Logic.sectionDependencies({ key: "a", enabledWhen: { key: "a" } }, ["a"]), [], "never itself");
        compare(Logic.sectionDependencies({ key: "c", visibleWhen: { key: "a", equals: "x" } }, ["a", "c"]), ["a"], "visibleWhen too");
        compare(Logic.sectionDependencies({ key: "c", visibleWhen: { capability: "touchpad" } }, ["a", "c"]), []);
    }

    function test_confirmation_batch() {
        let p = Logic.joinBatch(null, ["a"], 15);
        compare(p.secondsLeft, 15);
        p = Logic.tickBatch(p).pending;
        compare(p.secondsLeft, 14);
        p = Logic.joinBatch(p, ["b", "a"], 15);
        compare(p.keys, ["a", "b"]);
        compare(p.secondsLeft, 15, "joining restarts the countdown");
        let t = { pending: { keys: ["a"], secondsLeft: 1 } };
        t = Logic.tickBatch(t.pending);
        verify(t.expired);
        compare(t.pending, null);
    }
}
