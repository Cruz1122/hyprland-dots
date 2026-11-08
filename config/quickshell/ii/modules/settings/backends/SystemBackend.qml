import QtQuick
import Quickshell
import Quickshell.Io

// Optional tools on PATH, published as capabilities ("satty",
// "checkupdates") so entries can gate on them without the main shell
// running. Always available; owns no entries, so the write side of the
// backend interface only reports that nothing can be changed here.
QtObject {
    id: root

    readonly property string name: "system"
    readonly property bool available: true
    readonly property string unavailableReason: ""
    readonly property var tools: ["satty", "checkupdates"]
    property var found: ({})
    readonly property var capabilities: root.tools.filter(t => root.found[t] === true)

    signal succeeded(string key)
    signal failed(string key, string message)

    function read(entry) { return undefined; }
    function defaultValue(entry) { return undefined; }
    function isModified(entry) { return false; }
    function choices(entry) { return entry.options ?? []; }
    function write(entry, value) { root.failed(entry.key, "This setting cannot be changed here"); return false; }
    function reset(entry) { return root.write(entry, undefined); }
    function snapshot(entries) { return []; }
    function preview(entry, value) { return root.write(entry, value); }
    function persist(entries) { return false; }
    function restore(snap) { return true; }

    // Probed once at startup: `which` exits 0 when the tool is on PATH (the
    // same probe services/Updates.qml uses). Installing a tool needs a
    // restart of Settings to show up.
    readonly property Instantiator probes: Instantiator {
        model: root.tools
        delegate: Process {
            required property string modelData
            command: ["which", modelData]
            running: true
            stdout: StdioCollector {}
            onExited: (code, status) => {
                const next = Object.assign({}, root.found);
                next[modelData] = code === 0;
                root.found = next;
            }
        }
    }
}
