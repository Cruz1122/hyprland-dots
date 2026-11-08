import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.modules.common
import qs.modules.common.functions
import "../core/SettingsLogic.js" as Logic
import "DisplayLogic.js" as DisplayLogic

// Monitor layout (docs/settings.md, `display` backend).
//
// The value of display.monitors is the monitorsgen.py spec built from
// `hyprctl -j monitors all` (disabled outputs included). A preview evaluates
// the generated hl.monitor() calls with `hyprctl eval`; ~/.config/hypr/monitors.lua
// is written by monitorsgen.py only on confirm, and restore evaluates the
// layout captured before the preview. An existing monitors.lua without the
// marker is never overwritten implicitly: the monitorsFileUnmanaged
// capability shows the page's "Replace (keeps a backup)" action, which runs
// monitorsgen.py --force (it backs the file up first).
QtObject {
    id: root

    readonly property string name: "display"
    readonly property bool hyprlandRunning: (Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") ?? "").length > 0
    property bool loaded: false
    property string loadError: ""
    readonly property bool available: root.hyprlandRunning && root.loaded
    readonly property string unavailableReason: !root.hyprlandRunning ? "Hyprland is not running" : !root.loaded ? (root.loadError.length > 0 ? "Could not read the displays" : "Reading the displays…") : ""
    // Raw `hyprctl -j monitors all` objects.
    property var monitors: []
    // Layout shown while a preview is pending (live state may lag behind).
    property var _override: null
    readonly property var liveSpec: DisplayLogic.specFromMonitors(root.monitors)
    readonly property var values: ({ "display.monitors": root._override ?? root.liveSpec })
    // "missing", "managed" or "unmanaged".
    property string fileState: "missing"
    readonly property var capabilities: {
        const caps = [];
        if (root.monitors.length >= 2)
            caps.push("multiMonitor");
        if (root.fileState === "unmanaged")
            caps.push("monitorsFileUnmanaged");
        return caps;
    }
    property bool deferWrites: false

    readonly property string scriptPath: Quickshell.shellPath("scripts/settings/monitorsgen.py")
    readonly property string outputFile: DisplayLogic.outputPath(FileUtils.trimFileProtocol(Directories.home))

    signal succeeded(string key)
    signal failed(string key, string message)

    // Serialized jobs: { kind: "eval"|"write", spec, force, key }.
    property var _jobs: []

    function read(entry) { return root.values[entry.key]; }
    function defaultValue(entry) { return undefined; }
    function isModified(entry) { return false; }
    // Raw monitor objects for the page (modes, VRR support, descriptions).
    function choices(entry) { return root.monitors; }

    function _valid(key, spec) {
        const problem = DisplayLogic.validate(spec);
        if (problem.length > 0) {
            root.failed(key, problem);
            return false;
        }
        return true;
    }

    // Not reached through the registry (display.monitors is risky).
    function write(entry, value) {
        if (!root._valid(entry.key, value))
            return false;
        root._enqueue({ kind: "eval", spec: value, key: entry.key });
        root._enqueue({ kind: "write", spec: value, force: false, key: entry.key });
        return true;
    }

    function reset(entry) { return true; }

    function snapshot(entries) {
        return entries.map(e => ({ entry: e, spec: Logic.toPlain(root.liveSpec) }));
    }

    function preview(entry, value) {
        if (!root._valid(entry.key, value))
            return false;
        root._override = Logic.toPlain(value);
        root._enqueue({ kind: "eval", spec: root._override, key: entry.key });
        return true;
    }

    function persist(entries) {
        const spec = root._override ?? root.liveSpec;
        root._override = null;
        root._enqueue({ kind: "write", spec: spec, force: false, key: entries[0]?.key ?? "display.monitors" });
        return true;
    }

    function restore(snap) {
        root._override = null;
        for (const item of snap)
            root._enqueue({ kind: "eval", spec: item.spec, key: item.entry.key });
        return true;
    }

    function refresh() {
        if (!root.hyprlandRunning || root.monitorsProc.running)
            return;
        root.monitorsProc.running = true;
    }

    function _enqueue(job) {
        root._jobs = root._jobs.concat([job]);
        root._next();
    }

    function _next() {
        if (root.generator.running || root.evaluator.running || root._jobs.length === 0)
            return;
        const job = root._jobs[0];
        root._jobs = root._jobs.slice(1);
        root.generator.job = job;
        root.generator.command = DisplayLogic.generatorArgs(root.scriptPath, root.outputFile, job.spec,
            job.kind === "eval" ? "expr" : "write", job.force === true);
        root.generator.running = true;
    }

    readonly property Process generator: Process {
        property var job: null
        stdout: StdioCollector { id: generatorOut }
        stderr: StdioCollector { id: generatorErr }
        onExited: (exitCode, exitStatus) => {
            const job = root.generator.job;
            if (exitCode !== 0) {
                console.warn(`[DisplayBackend] monitorsgen.py exited ${exitCode}: ${generatorErr.text.trim()}`);
                root.failed(job.key, exitCode === 3
                    ? "monitors.lua was not created by Settings; use Replace to overwrite it"
                    : job.kind === "eval" ? "Could not apply the display layout" : "Could not save the display layout");
                root.monitorsFile.reload();
                root._next();
                return;
            }
            if (job.kind === "eval") {
                root.evaluator.job = job;
                root.evaluator.command = ["hyprctl", "eval", generatorOut.text.trim()];
                root.evaluator.running = true;
                return;
            }
            root.succeeded(job.key);
            root.monitorsFile.reload();
            root._next();
        }
    }

    readonly property Process evaluator: Process {
        property var job: null
        stdout: StdioCollector { id: evaluatorOut }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                console.warn(`[DisplayBackend] hyprctl eval exited ${exitCode}: ${evaluatorOut.text.trim()}`);
                root.failed(root.evaluator.job.key, "Could not apply the display layout");
            }
            root.refreshTimer.restart();
            root._next();
        }
    }

    // Hyprland reconfigures outputs asynchronously after eval.
    readonly property Timer refreshTimer: Timer {
        interval: 600
        onTriggered: root.refresh()
    }

    readonly property Process monitorsProc: Process {
        command: ["hyprctl", "-j", "monitors", "all"]
        stdout: StdioCollector { id: monitorsOut }
        onExited: (exitCode, exitStatus) => {
            try {
                if (exitCode !== 0)
                    throw new Error(`exit ${exitCode}`);
                const parsed = JSON.parse(monitorsOut.text);
                if (!Array.isArray(parsed))
                    throw new Error("not a list");
                // Reassigning identical data would rebuild the page's cards.
                if (!Logic.deepEqual(parsed, root.monitors))
                    root.monitors = parsed;
                root.loaded = true;
                root.loadError = "";
            } catch (error) {
                console.warn(`[DisplayBackend] cannot read hyprctl -j monitors all: ${error}`);
                root.loadError = String(error);
            }
        }
    }

    readonly property FileView monitorsFile: FileView {
        path: root.outputFile
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.fileState = DisplayLogic.isManagedText(text()) ? "managed" : "unmanaged"
        onLoadFailed: root.fileState = "missing"
    }

    // Hot-plugged outputs and config reloads show up without reopening the app.
    readonly property Connections hyprlandEvents: Connections {
        target: root.hyprlandRunning ? Hyprland : null
        function onRawEvent(event) {
            if (["monitoradded", "monitoraddedv2", "monitorremoved", "monitorremovedv2", "configreloaded"].includes(event.name))
                root.refreshTimer.restart();
        }
    }

    Component.onCompleted: root.refresh()
}
