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

    function test_capability_reasons() {
        compare(Logic.capabilityReason("satty"), "Requires satty, which is not installed");
        compare(Logic.capabilityReason("touchpad"), "No touchpad detected");
        compare(Logic.capabilityReason("ipc:regionRecord"), "The main shell is not running or is out of date");
        compare(Logic.capabilityReason("unknown"), "Not supported on this system");
        compare(Logic.capabilityReason("constructor"), "Not supported on this system");
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
