import QtQuick
import Quickshell
import Quickshell.Io
import "../core/SettingsLogic.js" as Logic
import "IpcLogic.js" as IpcLogic

// Settings held by the main shell (`qs -c ii`), reached with
// `qs -p <shell dir> ipc call …` as argv (docs/settings.md "Backends").
// Available while the main shell answers `ipc show`; values are re-read on
// every probe so changes made in the shell show up here.
//
// Pages run named calls themselves (IpcLogic.namedCallArgv) and gate them on
// the "ipc:<name>" capabilities published here.
QtObject {
    id: root

    readonly property string name: "ipc"
    property bool available: false
    property bool probed: false
    readonly property string unavailableReason: root.available ? ""
        : root.probed ? "The main shell is not running" : "Checking the main shell"
    property var values: ({})
    property var targets: ({})
    readonly property var capabilities: root.available
        ? IpcLogic.capabilitiesFor(root.targets)
        : []
    readonly property string shellDir: Quickshell.shellPath("")
    property int probeIntervalMs: 10000

    signal succeeded(string key)
    signal failed(string key, string message)

    function read(entry) {
        return root.values[entry.key];
    }

    function defaultValue(entry) {
        return IpcLogic.keySpec(entry.key)?.defaultValue;
    }

    function isModified(entry) {
        const v = root.read(entry);
        return v !== undefined && !Logic.deepEqual(v, root.defaultValue(entry));
    }

    function choices(entry) {
        return entry.options ?? [];
    }

    function _setValue(key, value) {
        const next = Object.assign({}, root.values);
        if (value === undefined)
            delete next[key];
        else
            next[key] = value;
        root.values = next;
    }

    // Optimistic: the value shows at once and is rolled back if the call fails.
    function write(entry, value) {
        const argv = IpcLogic.writeArgv(root.shellDir, entry.key, value);
        if (!argv) {
            root.failed(entry.key, "This setting cannot be changed here");
            return false;
        }
        if (!root.available) {
            root.failed(entry.key, root.unavailableReason);
            return false;
        }
        const previous = root.values[entry.key];
        root._setValue(entry.key, value);
        root._run(argv, (code, out) => {
            if (code === 0) {
                root.succeeded(entry.key);
            } else {
                root._setValue(entry.key, previous);
                root.failed(entry.key, "Could not reach the main shell");
            }
        });
        return true;
    }

    function reset(entry) {
        return root.write(entry, root.defaultValue(entry));
    }

    function snapshot(entries) {
        return entries.map(e => ({ entry: e, value: Logic.toPlain(root.read(e)) }));
    }

    function preview(entry, value) {
        return root.write(entry, value);
    }

    function persist(entries) {
        return true;
    }

    function restore(snap) {
        let ok = true;
        for (const item of snap) {
            if (item.value !== undefined)
                ok = root.write(item.entry, item.value) && ok;
        }
        return ok;
    }

    function refresh() {
        if (!showProc.running)
            showProc.running = true;
    }

    function _readValues() {
        for (const key in IpcLogic.KEYS) {
            const spec = IpcLogic.KEYS[key];
            if (!IpcLogic.hasFunction(root.targets, spec.target, spec.read)) {
                root._setValue(key, undefined);
                continue;
            }
            root._run(IpcLogic.readArgv(root.shellDir, key), (code, out) => {
                const decoded = code === 0 ? IpcLogic.decodeValue(spec.type, out) : { ok: false };
                root._setValue(key, decoded.ok ? decoded.value : undefined);
            });
        }
    }

    function _run(argv, done) {
        const proc = callComponent.createObject(root, { command: argv });
        proc.finished.connect((code, out) => {
            done(code, out);
            proc.destroy();
        });
        proc.running = true;
    }

    readonly property Component callComponent: Component {
        Process {
            id: proc
            signal finished(int code, string out)
            stdout: StdioCollector { id: out }
            onExited: (code, status) => proc.finished(code, out.text)
        }
    }

    readonly property Process showProc: Process {
        command: IpcLogic.showArgv(root.shellDir)
        stdout: StdioCollector { id: showOut }
        onExited: (code, status) => {
            const targets = code === 0 ? IpcLogic.parseShow(showOut.text) : {};
            root.targets = targets;
            root.available = code === 0 && Object.keys(targets).length > 0;
            root.probed = true;
            if (root.available)
                root._readValues();
            else
                root.values = {};
        }
    }

    readonly property Timer probeTimer: Timer {
        interval: root.probeIntervalMs
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }
}
