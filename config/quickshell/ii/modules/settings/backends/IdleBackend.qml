import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions
import "../core/SettingsLogic.js" as Logic
import "IdleLogic.js" as IdleLogic

// Idle timeouts (docs/settings.md, `idle` backend).
//
// The stored values are idle.* in config.json. scripts/settings/idlegen.py
// renders them into ~/.config/hypr/custom/shell-idle.conf, which
// hypridle.conf sources; hypridle only reads its config at start, so every
// apply restarts it (idlegen.py --restart). A preview renders the new values and restarts hypridle;
// config.json is written only on confirm; restore renders the previous
// values. Nothing is written on load: a file that does not match config.json
// is reported through the idleOutOfSync/idleUnmanaged capabilities instead.
QtObject {
    id: root

    readonly property string name: "idle"
    readonly property bool available: Config.ready
    readonly property string unavailableReason: Config.ready ? "" : "The configuration file is still loading"
    // key -> previewed value not yet in config.json.
    property var _pending: ({})
    readonly property var values: {
        const v = {};
        for (const key of IdleLogic.KEYS)
            v[key] = key in root._pending ? root._pending[key] : Logic.getPath(Config.options, key);
        return v;
    }
    // "unknown", "synced", "outOfSync" or "unmanaged".
    property string syncState: "unknown"
    readonly property var capabilities: root.syncState === "outOfSync" ? ["idleOutOfSync"]
        : root.syncState === "unmanaged" ? ["idleUnmanaged"] : []
    property bool deferWrites: false

    readonly property string scriptPath: Quickshell.shellPath("scripts/settings/idlegen.py")
    // hypridle.conf sources this exact path (`~` is HOME, not XDG_CONFIG_HOME).
    readonly property string outputFile: IdleLogic.outputPath(FileUtils.trimFileProtocol(Directories.home))

    signal succeeded(string key)
    signal failed(string key, string message)

    // Values the next apply renders, and the key to report its outcome on.
    property var _wanted: null
    property string _wantedKey: ""
    property bool _wantedForce: false

    function read(entry) { return root.values[entry.key]; }
    function defaultValue(entry) { return Logic.getPath(Config.defaults, entry.key); }
    function isModified(entry) { return !Logic.deepEqual(root.read(entry), root.defaultValue(entry)); }
    function choices(entry) { return IdleLogic.allowedChoices(entry.options, root.values, entry.key); }

    function _configValues() {
        const v = {};
        for (const key of IdleLogic.KEYS)
            v[key] = Logic.getPath(Config.options, key);
        return v;
    }

    function _check(key, values) {
        const problem = IdleLogic.orderProblem(values);
        if (problem.length > 0) {
            root.failed(key, problem);
            return false;
        }
        return true;
    }

    // Non-risky path (not used by the registry, where idle entries are risky):
    // store and apply at once.
    function write(entry, value) {
        if (!root._check(entry.key, IdleLogic.withValue(root.values, entry.key, value)))
            return false;
        if (!Logic.setPath(Config.options, entry.key, value)) {
            root.failed(entry.key, "Unknown configuration path");
            return false;
        }
        root._apply(entry.key, root._configValues(), false);
        return true;
    }

    function reset(entry) { return root.write(entry, Logic.toPlain(root.defaultValue(entry))); }

    function snapshot(entries) {
        return entries.map(e => ({ entry: e, value: Logic.toPlain(Logic.getPath(Config.options, e.key)) }));
    }

    function preview(entry, value) {
        const next = IdleLogic.withValue(root.values, entry.key, value);
        if (!root._check(entry.key, next))
            return false;
        const pending = Object.assign({}, root._pending);
        pending[entry.key] = value;
        root._pending = pending;
        root._apply(entry.key, next, false);
        return true;
    }

    // The file already holds the previewed values; only config.json is left.
    function persist(entries) {
        let ok = true;
        const pending = Object.assign({}, root._pending);
        for (const e of entries) {
            if (!(e.key in pending))
                continue;
            ok = Logic.setPath(Config.options, e.key, pending[e.key]) && ok;
            delete pending[e.key];
        }
        root._pending = pending;
        root.refreshSync();
        return ok;
    }

    function restore(snap) {
        const pending = Object.assign({}, root._pending);
        for (const item of snap)
            delete pending[item.entry.key];
        root._pending = pending;
        root._apply(snap[0]?.entry?.key ?? "", root.values, false);
        root.refreshSync();
        return true;
    }

    // Coalesces bursts (restore runs once per entry) into one render.
    function _apply(key, values, force) {
        root._wanted = values;
        root._wantedKey = key;
        root._wantedForce = force;
        root.applyTimer.restart();
    }

    function _run() {
        if (root.generator.running || root._wanted === null)
            return;
        const values = root._wanted;
        root.generator.reportKey = root._wantedKey;
        root.generator.command = IdleLogic.generatorArgs(root.scriptPath, root.outputFile, values, "write", root._wantedForce).concat(["--restart"]);
        root._wanted = null;
        root.generator.running = true;
    }

    function _report(key, message) {
        if (key.length > 0)
            root.failed(key, message);
        else
            console.warn(`[IdleBackend] ${message}`);
    }

    function refreshSync() {
        root.syncTimer.restart();
    }

    function _checkSync() {
        // While a preview is pending the file differs from config.json on purpose.
        if (!Config.ready || Object.keys(root._pending).length > 0)
            return;
        if (root.checker.running) {
            root.syncTimer.restart();
            return;
        }
        root.checker.command = IdleLogic.generatorArgs(root.scriptPath, root.outputFile, root._configValues(), "print", false);
        root.checker.running = true;
    }

    readonly property Timer syncTimer: Timer {
        interval: 400
        onTriggered: root._checkSync()
    }

    readonly property Timer applyTimer: Timer {
        interval: 50
        onTriggered: root._run()
    }

    // idlegen.py --restart restarts hypridle (it reads its config only at
    // start) so the new instance outlives this process.
    readonly property Process generator: Process {
        property string reportKey: ""
        stderr: StdioCollector { id: generatorErr }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                root._report(root.generator.reportKey, exitCode === 3
                    ? "shell-idle.conf was edited by hand; replace it first"
                    : exitCode === 4 ? "Could not restart hypridle" : "Could not write the idle settings");
                if (exitCode !== 3)
                    console.warn(`[IdleBackend] idlegen.py exited ${exitCode}: ${generatorErr.text.trim()}`);
            }
            root._run();
        }
    }

    readonly property Process checker: Process {
        stdout: StdioCollector { id: checkerOut }
        onExited: (exitCode, exitStatus) => {
            if (Object.keys(root._pending).length > 0)
                return;
            if (exitCode !== 0) {
                // config.json holds values idlegen rejects (edited by hand).
                root.syncState = "outOfSync";
                return;
            }
            const values = root._configValues();
            root.syncState = IdleLogic.syncState(checkerOut.text, root.idleFile.loadedText, root.idleFile.present, IdleLogic.allNever(values));
        }
    }

    readonly property FileView idleFile: FileView {
        property string loadedText: ""
        property bool present: false
        path: root.outputFile
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            root.idleFile.loadedText = text();
            root.idleFile.present = true;
            root.refreshSync();
        }
        onLoadFailed: {
            root.idleFile.loadedText = "";
            root.idleFile.present = false;
            root.refreshSync();
        }
    }

    // Comparing against config.json (not previews) keeps the warning about
    // what is stored, and a confirm or revert settles it.
    readonly property Connections configEvents: Connections {
        target: Config
        function onReadyChanged() { root.refreshSync(); }
    }
}
