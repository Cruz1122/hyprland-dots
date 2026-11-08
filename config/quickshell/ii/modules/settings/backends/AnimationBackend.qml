import QtQuick

// Placeholder of the `animation` backend (docs/settings.md "Backends"): the
// registry may already name it, but nothing can be read or written yet, so
// every entry renders disabled with `unavailableReason`. It keeps the full
// backend interface so SettingsStoreImpl can route to it like any other.
// TODO(settings phase A1, ~/.claude/plans/settings-p2-animations-guidance.md):
// replace this body with the real backend (custom/shell-animations.lua
// through animationsgen.py, applied live with hyprctl eval).
QtObject {
    id: root

    readonly property string name: "animation"
    readonly property bool available: false
    readonly property string unavailableReason: "Animation settings are not available yet"
    readonly property var values: ({})
    readonly property var capabilities: []
    readonly property bool busy: false

    signal succeeded(string key)
    signal failed(string key, string message)

    function flush() {}
    function read(entry) { return undefined; }
    function defaultValue(entry) { return undefined; }
    function isModified(entry) { return false; }
    function write(entry, value) {
        root.failed(entry.key, "Animation settings are not available yet");
        return false;
    }
    function reset(entry) { return root.write(entry, undefined); }
    function snapshot(entries) { return []; }
    function preview(entry, value) { return false; }
    function persist(entries) { return false; }
    function restore(snap) { return false; }
}
