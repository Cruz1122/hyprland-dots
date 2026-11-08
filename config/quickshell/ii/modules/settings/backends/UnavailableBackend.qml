import QtQuick

// Backend that implements the full interface (docs/settings.md "Backends")
// but is not available yet. Placeholder backends extend it; their owners
// replace the whole file with a real implementation.
QtObject {
    id: root

    property string name: ""
    readonly property bool available: false
    readonly property string unavailableReason: "Not implemented yet"
    readonly property var values: ({})
    readonly property var capabilities: []

    signal succeeded(string key)
    signal failed(string key, string message)

    function read(entry) { return root.values[entry.key]; }
    function defaultValue(entry) { return undefined; }
    function isModified(entry) { return false; }
    function choices(entry) { return entry.options ?? []; }
    function write(entry, value) { root.failed(entry.key, root.unavailableReason); return false; }
    function reset(entry) { return root.write(entry, undefined); }
    function snapshot(entries) { return []; }
    function preview(entry, value) { return root.write(entry, value); }
    function persist(entries) { return false; }
    function restore(snap) { return true; }
}
