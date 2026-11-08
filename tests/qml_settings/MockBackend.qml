import QtQuick
import "../../config/quickshell/ii/modules/settings/core/SettingsLogic.js" as Logic

// In-memory backend implementing the docs/settings.md interface.
QtObject {
    id: root

    property string name: "mock"
    property bool available: true
    property string unavailableReason: ""
    property var values: ({})
    property var defaults: ({})
    property var capabilities: []
    property bool rejectWrites: false
    // Values applied live but not yet persisted (risky previews).
    property var previewed: ({})
    property var persisted: []
    property int writeCount: 0
    // Called with (entry, value) at the start of preview(), to observe ordering.
    property var previewHook: null
    // Shutdown support (SettingsStoreImpl.finish). With asyncRestore,
    // restore() is busy for restoreDelayMs, like a backend running a command.
    property bool busy: false
    property bool asyncRestore: false
    property int restoreDelayMs: 150
    property int flushCount: 0
    property var _restoreSnap: null

    function flush() { root.flushCount++; }

    readonly property Timer _restoreTimer: Timer {
        interval: root.restoreDelayMs
        onTriggered: {
            for (const item of root._restoreSnap)
                root._set(item.key, item.value);
            root._restoreSnap = null;
            root.busy = false;
        }
    }

    signal succeeded(string key)
    signal failed(string key, string message)

    function read(entry) { return root.values[entry.key]; }
    function defaultValue(entry) { return root.defaults[entry.key]; }
    function isModified(entry) { return !Logic.deepEqual(root.values[entry.key], root.defaults[entry.key]); }
    function choices(entry) { return entry.options ?? []; }

    function _set(key, value) {
        const next = Object.assign({}, root.values);
        next[key] = value;
        root.values = next;
    }

    function write(entry, value) {
        if (root.rejectWrites) {
            root.failed(entry.key, "Rejected by backend");
            return false;
        }
        root.writeCount++;
        root._set(entry.key, value);
        root.succeeded(entry.key);
        return true;
    }

    function reset(entry) { return root.write(entry, root.defaults[entry.key]); }
    function snapshot(entries) { return entries.map(e => ({ key: e.key, value: root.values[e.key] })); }

    function preview(entry, value) {
        if (typeof root.previewHook === "function")
            root.previewHook(entry, value);
        root._set(entry.key, value);
        const p = Object.assign({}, root.previewed);
        p[entry.key] = value;
        root.previewed = p;
        return true;
    }

    function persist(entries) {
        root.persisted = root.persisted.concat(entries.map(e => e.key));
        root.previewed = ({});
        return true;
    }

    function restore(snap) {
        root.previewed = ({});
        if (root.asyncRestore) {
            root._restoreSnap = snap;
            root.busy = true;
            root._restoreTimer.restart();
            return true;
        }
        for (const item of snap)
            root._set(item.key, item.value);
        return true;
    }
}
