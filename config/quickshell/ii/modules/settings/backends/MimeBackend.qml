import QtQuick
import Quickshell
import Quickshell.Io
import "MimeLogic.js" as MimeLogic

// Default applications through scripts/settings/default-apps.py (argv only).
// The list is loaded lazily, on the first read of a `mime.*` entry (the
// Applications page), because scanning desktop files is not free and most
// sessions never open that page. One `set` runs at a time; its output
// refreshes the role it changed.
QtObject {
    id: root

    readonly property string name: "mime"
    readonly property string script: Quickshell.shellPath("scripts/settings/default-apps.py")
    property var roles: ({})
    property bool loaded: false
    property string loadError: ""
    readonly property bool available: root.loaded && root.loadError === ""
    readonly property string unavailableReason: root.loadError !== "" ? root.loadError : (root.loaded ? "" : "Loading default applications")
    readonly property var values: MimeLogic.valuesFrom(root.roles)
    readonly property var capabilities: []

    // Mutated, never reassigned: ensureLoaded() runs inside row bindings, and
    // writing a notifying property there would make each binding depend on it.
    readonly property var _load: ({ requested: false })
    property var _pending: null

    signal succeeded(string key)
    signal failed(string key, string message)

    function ensureLoaded() {
        if (root._load.requested)
            return;
        root._load.requested = true;
        // Deferred: reads happen inside binding evaluation.
        Qt.callLater(() => listProc.running = true);
    }

    function read(entry) {
        root.ensureLoaded();
        return root.values[entry.key];
    }

    function defaultValue(entry) { return undefined; }
    function isModified(entry) { return false; }

    function choices(entry) {
        root.ensureLoaded();
        return MimeLogic.choices(root.roles[MimeLogic.roleOf(entry)]);
    }

    function write(entry, value) {
        if (setProc.running) {
            root.failed(entry.key, "Another change is still being applied");
            return false;
        }
        root._pending = entry;
        setProc.command = ["python3", root.script, "set", MimeLogic.roleOf(entry), String(value)];
        setProc.running = true;
        return true;
    }

    function reset(entry) { return true; }
    function snapshot(entries) { return entries.map(e => ({ entry: e, value: root.values[e.key] })); }
    function preview(entry, value) { return root.write(entry, value); }
    function persist(entries) { return true; }
    function restore(snap) { return true; }

    readonly property Process listProc: Process {
        command: ["python3", root.script, "list", "--json"]
        stdout: StdioCollector { id: listOut }
        stderr: StdioCollector { id: listErr }
        onExited: (exitCode, exitStatus) => {
            const parsed = exitCode === 0 ? MimeLogic.parseList(listOut.text) : null;
            if (parsed && parsed.ok) {
                root.roles = parsed.roles;
                root.loadError = "";
            } else {
                root.loadError = parsed ? parsed.error : MimeLogic.errorMessage(listErr.text, "Could not read the default applications");
            }
            root.loaded = true;
        }
    }

    readonly property Process setProc: Process {
        stdout: StdioCollector { id: setOut }
        stderr: StdioCollector { id: setErr }
        onExited: (exitCode, exitStatus) => {
            const entry = root._pending;
            root._pending = null;
            if (!entry)
                return;
            const parsed = exitCode === 0 ? MimeLogic.parseSet(setOut.text) : null;
            if (parsed && parsed.ok) {
                root.roles = MimeLogic.withRole(root.roles, parsed.role, parsed.state);
                root.succeeded(entry.key);
            } else {
                root.failed(entry.key, parsed ? parsed.error : MimeLogic.errorMessage(setErr.text, "Could not change the default application"));
            }
        }
    }
}
