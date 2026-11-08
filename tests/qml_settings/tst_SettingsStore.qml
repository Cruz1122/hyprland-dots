import QtQuick
import QtTest
import "../../config/quickshell/ii/modules/settings/core"
import "../../config/quickshell/ii/modules/settings/core/SettingsLogic.js" as Logic

TestCase {
    id: testCase
    name: "SettingsStore"

    readonly property var model: Logic.buildRegistry(
        { groups: [{ id: "g", title: "G", pages: ["p", "q"] }], footer: [] },
        {
            p: {
                id: "p", title: "P", sections: [{ id: "s", title: "S" }],
                entries: [
                    { key: "flag", section: "s", label: "Flag", backend: "config", type: "bool" },
                    { key: "count", section: "s", label: "Count", backend: "config", type: "int", min: 0, max: 10 },
                    { key: "mode", section: "s", label: "Mode", backend: "config", type: "enum", options: [{ value: "a" }, { value: "b" }] },
                    { key: "city", section: "s", label: "City", backend: "config", type: "string", validate: { maxLength: 5 } },
                    { key: "dep", section: "s", label: "Dep", backend: "config", type: "bool", enabledWhen: { key: "flag", equals: true } },
                    { key: "slotA", section: "s", label: "A", backend: "config", type: "string", validate: { unique: "slots" } },
                    { key: "slotB", section: "s", label: "B", backend: "config", type: "string", validate: { unique: "slots" } },
                    { key: "layout", section: "s", label: "Layout", backend: "hyprland", type: "string", risky: true },
                    { key: "scale", section: "s", label: "Scale", backend: "hyprland", type: "real", risky: true, min: 0.5, max: 3 },
                    { key: "idle.lock", section: "s", label: "Lock", backend: "idle", type: "int", risky: true, min: 0, max: 60 },
                    { key: "hidden", section: "s", label: "Hidden", backend: "config", type: "bool", visibleWhen: { capability: "touchpad" } },
                    { key: "gone", section: "s", label: "Gone", backend: "display", type: "bool" },
                    { key: "info", section: "s", label: "Info", backend: "readonly", type: "info" },
                    { key: "cfginfo", section: "s", label: "Config info", backend: "config", type: "info" }
                ]
            },
            q: { id: "q", title: "Q", sections: [{ id: "x", title: "X" }], entries: [{ ref: "count", section: "x" }] }
        },
        { retired: [], managedElsewhere: [] })

    QtObject {
        id: registry
        function entry(key) { return testCase.model.entryByKey[key] ?? null; }
        function entriesForPage(id) { return testCase.model.pageById[id]?.entries ?? []; }
        function allEntries() { return Object.values(testCase.model.entryByKey); }
    }

    MockBackend {
        id: config
        name: "config"
        capabilities: ["battery"]
        property bool deferWrites: false
        property var deferLog: []
        onDeferWritesChanged: config.deferLog = config.deferLog.concat([config.deferWrites])
    }

    MockBackend {
        id: risky
        name: "risky"
        property var deferSeenAtPreview: []
        previewHook: () => risky.deferSeenAtPreview = risky.deferSeenAtPreview.concat([config.deferWrites])
    }

    // Backend whose reset value is unknown up front (Hyprland drops an override).
    MockBackend {
        id: overrides
        name: "idle"
        property int previewResets: 0
        function previewReset(entry) {
            overrides.previewResets++;
            overrides._set(entry.key, 0);
            return true;
        }
    }

    MockBackend {
        id: off
        name: "off"
        available: false
        unavailableReason: "Not implemented yet"
    }

    SettingsStoreImpl {
        id: store
        registry: registry
        backends: ({ config: config, hyprland: risky, display: off, idle: overrides })
    }

    SignalSpy { id: failedSpy; target: store; signalName: "failed" }
    SignalSpy { id: committedSpy; target: store; signalName: "committed" }

    function init() {
        store.cancelFinish();
        for (const b of [config, risky, overrides]) {
            b._restoreTimer.stop();
            b._restoreSnap = null;
            b.asyncRestore = false;
            b.busy = false;
            b.flushCount = 0;
        }
        store.revert();
        config.statusNoteFor = null;
        const defaults = { flag: false, count: 3, mode: "a", city: "", dep: false, slotA: "x", slotB: "y", hidden: false };
        config.defaults = defaults;
        config.values = Object.assign({}, defaults);
        config.rejectWrites = false;
        risky.defaults = { layout: "us", scale: 1 };
        risky.values = { layout: "us", scale: 1 };
        risky.persisted = [];
        risky.deferSeenAtPreview = [];
        config.deferLog = [];
        overrides.defaults = { "idle.lock": 0 };
        overrides.values = { "idle.lock": 0 };
        overrides.persisted = [];
        overrides.previewResets = 0;
        failedSpy.clear();
        committedSpy.clear();
    }

    function test_write_coerces_and_commits() {
        verify(store.write("count", 7.4));
        compare(store.value("count"), 7);
        compare(committedSpy.count, 1);
        verify(store.write("count", 50));
        compare(store.value("count"), 10, "clamped to max");
        verify(store.write("city", 10001 % 100000));
        compare(store.value("city"), "10001", "numeric text stays a string");
    }

    function test_rejected_writes_emit_failed_and_keep_value() {
        verify(!store.write("mode", "zzz"));
        compare(store.value("mode"), "a");
        verify(!store.write("city", "too long text"));
        verify(!store.write("flag", "yes"));
        verify(!store.write("unknown.key", 1));
        compare(failedSpy.count, 4);
        config.rejectWrites = true;
        verify(!store.write("flag", true));
        compare(store.value("flag"), false);
    }

    // statusNote(entry) is an optional backend hook; the store passes the
    // English text through and returns "" without it.
    function test_status_note_passthrough() {
        compare(store.statusNote("flag"), "", "the hook has nothing to say");
        config.statusNoteFor = e => e.key === "flag" ? "Paused by Game Mode" : "";
        compare(store.statusNote("flag"), "Paused by Game Mode");
        compare(store.statusNote("count"), "");
        config.statusNoteFor = () => 42;
        compare(store.statusNote("flag"), "", "only strings pass");
        config.statusNoteFor = null;
        off.statusNoteFor = () => "Paused by Game Mode";
        compare(store.statusNote("gone"), "", "unavailable backend");
        off.statusNoteFor = null;
        compare(store.statusNote("info"), "", "read-only entries");
        // backendFor skips entries that are not writable, so a read-only entry
        // gets "" even when its backend has the hook.
        config.statusNoteFor = () => "Paused by Game Mode";
        compare(store.statusNote("flag"), "Paused by Game Mode");
        compare(store.statusNote("cfginfo"), "", "read-only entry on a backend with the hook");
        config.statusNoteFor = null;
        compare(store.statusNote("unknown.key"), "");
    }

    // A backend may not know a default (Hyprland before the base config is
    // read): defaultValue stays undefined instead of a made-up value.
    function test_unknown_default_stays_undefined() {
        config.defaults = Object.assign({}, config.defaults, { count: undefined });
        compare(store.defaultValue("count"), undefined);
        compare(Logic.resetText(store.entry("count"), store.defaultValue("count"), t => t), "Reset");
        compare(store.defaultValue("gone"), undefined, "unavailable backend");
        compare(Logic.resetText(store.entry("flag"), store.defaultValue("flag"), t => t), "Reset to Off");
    }

    // With the backend down the store reports no value, no modification and
    // the backend's reason, so rows render "—" and the section banner.
    function test_unavailable_backend_has_no_value() {
        off.values = { gone: true };
        off.defaults = { gone: false };
        compare(store.isAvailable("gone"), false);
        compare(store.isEnabled("gone"), false);
        compare(store.isModified("gone"), false, "no modified dot or reset button");
        compare(store.unavailableReason("gone"), "Not implemented yet");
        verify(!store.write("gone", false), "writes are refused");
        verify(!store.reset("gone"));
        compare(off.values.gone, true, "the backend is not touched");
        off.values = ({});
        off.defaults = ({});
    }

    function test_unchanged_value_does_not_write() {
        const before = config.writeCount;
        verify(store.write("mode", "a"));
        compare(config.writeCount, before);
    }

    function test_modified_and_reset() {
        verify(!store.isModified("count"));
        store.write("count", 5);
        verify(store.isModified("count"));
        verify(store.reset("count"));
        compare(store.value("count"), 3);
        verify(!store.isModified("count"));
        store.write("count", 6);
        store.write("mode", "b");
        verify(store.resetPage("p"));
        verify(!store.isModified("count"));
        verify(!store.isModified("mode"));
        store.write("count", 6);
        verify(store.resetPage("q"), "aliases reset their canonical key");
        verify(!store.isModified("count"));
    }

    function test_reset_page_skips_hidden_rows() {
        config._set("hidden", true);
        store.write("count", 6);
        verify(!store.isVisible("hidden"));
        compare(store.modifiedCount("p"), 1, "hidden rows are not counted");
        verify(store.resetPage("p"));
        verify(!store.isModified("count"));
        compare(store.value("hidden"), true, "hidden rows are not reset");
        compare(store.modifiedCount("p"), 0);
        compare(store.modifiedCount("q"), 0);
        store.write("count", 6);
        compare(store.modifiedCount("q"), 1, "aliases count their canonical key");
    }

    function test_conditions_and_availability() {
        verify(!store.isEnabled("dep"));
        verify(!store.write("dep", true), "disabled entries reject writes");
        store.write("flag", true);
        verify(store.isEnabled("dep"));
        verify(store.write("dep", true));
        verify(!store.isAvailable("gone"));
        compare(store.unavailableReason("gone"), "Not implemented yet");
        verify(!store.write("gone", true));
        verify(store.isAvailable("info"), "read-only entries are always available");
        verify(!store.write("info", "x"));
        verify(store.hasCapability("battery"));
        verify(!store.hasCapability("touchpad"));
    }

    function test_unique_group() {
        verify(!store.write("slotA", "y"), "value used by slotB");
        verify(store.write("slotA", "z"));
    }

    function test_risky_confirm() {
        verify(store.write("layout", "de"));
        compare(store.value("layout"), "de", "previewed live");
        compare(store.pendingConfirmation.keys, ["layout"]);
        compare(store.pendingConfirmation.secondsLeft, 15);
        store.confirm();
        compare(store.pendingConfirmation, null);
        compare(risky.persisted, ["layout"]);
        compare(store.value("layout"), "de");
    }

    function test_risky_revert_restores_batch() {
        store.write("layout", "de");
        store.write("scale", 2);
        store.write("layout", "fr");
        compare(store.pendingConfirmation.keys, ["layout", "scale"]);
        store.revert();
        compare(store.pendingConfirmation, null);
        compare(store.value("layout"), "us", "first snapshot wins");
        compare(store.value("scale"), 1);
        compare(risky.persisted, []);
    }

    function test_risky_timeout_reverts_and_join_restarts() {
        store.confirmSeconds = 2;
        store.write("layout", "de");
        wait(1300);
        compare(store.pendingConfirmation.secondsLeft, 1);
        store.write("scale", 2);
        compare(store.pendingConfirmation.secondsLeft, 2, "joining restarts the countdown");
        tryCompare(store, "pendingConfirmation", null, 4000);
        compare(store.value("layout"), "us");
        compare(store.value("scale"), 1);
        store.confirmSeconds = 15;
    }

    function test_risky_reset_needs_confirmation() {
        store.write("scale", 2);
        store.confirm();
        verify(store.reset("scale"));
        verify(store.pendingConfirmation !== null);
        compare(store.value("scale"), 1);
        store.revert();
        compare(store.value("scale"), 2);
    }

    function test_defer_writes_spans_the_risky_batch() {
        verify(!config.deferWrites);
        store.write("layout", "de");
        compare(risky.deferSeenAtPreview, [true], "set before the first preview");
        store.write("scale", 2);
        compare(config.deferLog, [true], "set once per batch");
        store.confirm();
        verify(!config.deferWrites, "released after persist");
        store.write("layout", "fr");
        store.revert();
        verify(!config.deferWrites, "released after restore");
        store.confirmSeconds = 1;
        store.write("layout", "it");
        verify(config.deferWrites);
        tryCompare(config, "deferWrites", false, 3000);
        store.confirmSeconds = 15;
        compare(config.deferLog, [true, false, true, false, true, false]);
    }

    function test_risky_reset_uses_preview_reset_when_available() {
        verify(store.write("idle.lock", 10));
        store.confirm();
        compare(store.value("idle.lock"), 10);
        verify(store.reset("idle.lock"));
        compare(overrides.previewResets, 1);
        compare(store.pendingConfirmation.keys, ["idle.lock"]);
        verify(config.deferWrites);
        compare(store.value("idle.lock"), 0);
        store.revert();
        compare(store.value("idle.lock"), 10, "revert restores the snapshot");
        store.reset("idle.lock");
        store.confirm();
        compare(overrides.persisted, ["idle.lock", "idle.lock"]);
        compare(store.value("idle.lock"), 0);
    }

    // Regression: closing the window reverted a pending preview and quit at
    // once, so restores that run commands (idle, displays, Hyprland) never
    // ran and the preview stayed applied.
    function test_finish_reverts_and_waits_for_busy_backends() {
        risky.asyncRestore = true;
        verify(store.write("layout", "de"));
        let finished = 0;
        store.finish(() => finished++);
        compare(store.pendingConfirmation, null, "pending batch reverted");
        verify(risky.busy, "restore still running");
        compare(store.busyBackends(), ["hyprland"]);
        wait(80);
        compare(finished, 0, "does not finish while a backend is busy");
        tryVerify(() => finished === 1, 2000);
        compare(store.value("layout"), "us");
        wait(120);
        compare(finished, 1, "done runs once");
    }

    function test_finish_flushes_debounced_writes() {
        let finished = 0;
        store.finish(() => finished++);
        compare(config.flushCount, 1);
        compare(risky.flushCount, 1);
        tryVerify(() => finished === 1, 1000);
    }

    function test_finish_gives_up_after_the_timeout() {
        risky.busy = true;
        let finished = 0;
        store.finish(() => finished++, 250);
        wait(100);
        compare(finished, 0);
        tryVerify(() => finished === 1, 2000);
    }

    function test_cancel_finish_keeps_the_session() {
        risky.busy = true;
        let finished = 0;
        store.finish(() => finished++, 200);
        store.cancelFinish();
        wait(400);
        compare(finished, 0);
    }
}
