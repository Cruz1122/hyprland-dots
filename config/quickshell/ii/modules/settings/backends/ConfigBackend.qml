import QtQuick
import qs.modules.common
import "../core/SettingsLogic.js" as Logic

// config.json through Config. Values are read from Config.options so row
// bindings track the exact property. Writes assign the already-typed value to
// the nested property; Config.setNestedValue is avoided on purpose because it
// turns numeric strings ("10001") into numbers.
QtObject {
    id: root

    readonly property string name: "config"
    readonly property bool available: Config.ready
    readonly property string unavailableReason: Config.ready ? "" : "The configuration file is still loading"
    readonly property var values: ({})
    readonly property var capabilities: []
    // Before quitting (SettingsStore.finish): a write still waiting for Config's delay.
    readonly property bool busy: Config.writePending

    signal succeeded(string key)
    signal failed(string key, string message)

    function flush() {
        Config.flushWrites();
    }

    function read(entry) {
        return Logic.getPath(Config.options, entry.path);
    }

    function defaultValue(entry) {
        return Logic.getPath(Config.defaults, entry.path);
    }

    function isModified(entry) {
        return !Logic.deepEqual(root.read(entry), root.defaultValue(entry));
    }

    function write(entry, value) {
        if (!Logic.setPath(Config.options, entry.path, value)) {
            console.warn(`[ConfigBackend] unknown configuration path ${entry.path}`);
            root.failed(entry.key, "Unknown configuration path");
            return false;
        }
        root.succeeded(entry.key);
        return true;
    }

    function reset(entry) {
        return root.write(entry, Logic.toPlain(root.defaultValue(entry)));
    }

    function snapshot(entries) {
        return entries.map(e => ({ entry: e, value: Logic.toPlain(root.read(e)) }));
    }

    // config.json has no live-only state: a preview is a normal write, and
    // restore writes the snapshot back.
    function preview(entry, value) {
        return root.write(entry, value);
    }

    function persist(entries) {
        return true;
    }

    function restore(snap) {
        let ok = true;
        for (const item of snap)
            ok = root.write(item.entry, item.value) && ok;
        return ok;
    }
}
