import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.modules.common
import qs.modules.common.functions
import "HyprlandLogic.js" as HL

// Hyprland options (docs/settings.md, `hyprland` backend).
//
// Effective values come from one `hyprctl -j descriptions` at start and after
// every `configreloaded`. Overrides live in ~/.config/hypr/custom/shell-settings.lua
// and are written only through scripts/hyprland/hyprconfigurator.py (argv,
// typed values); writing that file makes Hyprland autoreload, which in turn
// refreshes the effective values. Hyprland only watches the file once its
// config has loaded it (hyprland.lua requires it only if it exists), so a
// write that no `configreloaded` follows within reloadGraceMs ends with one
// `hyprctl reload config-only` (monitors untouched). Never `keyword`.
//
// Risky entries preview with `hyprctl eval 'hl.config({...})'` and persist on
// confirm. While the store holds a confirmation (`deferWrites`), normal file
// writes wait, because the reload they trigger would drop the live preview.
QtObject {
    id: root

    readonly property string name: "hyprland"
    readonly property bool hyprlandRunning: (Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") ?? "").length > 0
    property bool loaded: false
    property string loadError: ""
    readonly property bool available: root.hyprlandRunning && root.loaded
    readonly property string unavailableReason: !root.hyprlandRunning ? "Hyprland is not running" : !root.loaded ? (root.loadError.length > 0 ? "Could not read the Hyprland options" : "Reading the Hyprland options…") : ""
    // getoption name -> effective value as reported by Hyprland.
    property var values: ({})
    property var defaults: ({})
    // Override key (input:kb_layout) -> value stored in shell-settings.lua.
    property var overrides: ({})
    property bool touchpad: false
    property bool gameMode: false
    readonly property var capabilities: {
        const caps = [];
        if (root.touchpad)
            caps.push("touchpad");
        if (root.gameMode)
            caps.push("gameMode");
        return caps;
    }
    property bool deferWrites: false
    // Work the app waits for before quitting (SettingsStore.finish): debounced
    // writes, queued commands and a pending reload fallback. Reads are not.
    readonly property bool busy: root.flushTimer.running || Object.keys(root._queue).length > 0
        || root.runner.running || root._jobs.length > 0 || root.reloadFallback.running

    readonly property string scriptPath: Quickshell.shellPath("scripts/hyprland/hyprconfigurator.py")
    readonly property string configDir: FileUtils.trimFileProtocol(Directories.config)
    readonly property string settingsFile: `${root.configDir}/hypr/custom/shell-settings.lua`
    readonly property string shellOverridesFile: `${root.configDir}/hypr/hyprland/shellOverrides/main.lua`
    readonly property string header: "Managed by the illogical-impulse settings app. Edit through the app; manual changes may be overwritten."

    signal succeeded(string key)
    signal failed(string key, string message)

    // Entries the rows have read, to announce external changes: key -> entry.
    property var _seen: ({})
    // key -> value shown until Hyprland reports the change.
    property var _optimistic: ({})
    // path -> { entry, op: "set"|"unset", value } waiting for the debounce.
    property var _queue: ({})
    // key -> { entry, value } applied live with hyprctl eval, not yet persisted.
    property var _live: ({})
    // Serial queue of mutating commands: [{ argv, done(code, stderr, startedAt) }].
    property var _jobs: []
    // Date.now() of the last `configreloaded`.
    property real _lastReloadAt: 0
    // Autoreload follows a write in well under a second (0.6 s measured).
    property int reloadGraceMs: 2000

    function _note(entry) {
        if (!root._seen[entry.key])
            root._seen[entry.key] = entry;
    }

    function _effective(entry) {
        return HL.fromHypr(entry, root.values[entry.option]);
    }

    function read(entry) {
        root._note(entry);
        if (entry.key in root._optimistic)
            return root._optimistic[entry.key];
        return root._effective(entry);
    }

    // Hyprland's compiled default, not the user's base config: reference only.
    function defaultValue(entry) {
        return HL.fromHypr(entry, root.defaults[entry.option]);
    }

    function isModified(entry) {
        const queued = root._queue[entry.path];
        if (queued)
            return queued.op === "set";
        return HL.overrideKey(entry.path) in root.overrides;
    }

    function choices(entry) {
        if (entry.path === "input.kb_layout")
            return root.xkb.parsed.layouts;
        return entry.options ?? [];
    }

    function _setOptimistic(key, value) {
        const next = Object.assign({}, root._optimistic);
        if (value === undefined)
            delete next[key];
        else
            next[key] = value;
        root._optimistic = next;
    }

    function _validEntry(entry) {
        if (!HL.isLuaPath(entry.path)) {
            console.warn(`[HyprlandBackend] invalid Lua path ${entry.path}`);
            root.failed(entry.key, "Invalid Hyprland option");
            return false;
        }
        return true;
    }

    function write(entry, value) {
        if (!root._validEntry(entry))
            return false;
        if (!HL.isControlFree(HL.toArg(entry, value))) {
            root.failed(entry.key, "Invalid characters in the value");
            return false;
        }
        root._enqueue(entry, "set", value);
        root._setOptimistic(entry.key, value);
        return true;
    }

    function reset(entry) {
        if (!root._validEntry(entry))
            return false;
        root._enqueue(entry, "unset", undefined);
        root._setOptimistic(entry.key, undefined);
        return true;
    }

    function _enqueue(entry, op, value) {
        const next = Object.assign({}, root._queue);
        next[entry.path] = { entry: entry, op: op, value: value };
        root._queue = next;
        if (!root.deferWrites)
            root.flushTimer.restart();
    }

    function _configuratorArgs(ops) {
        let argv = ["python3", root.scriptPath, "--file", root.settingsFile, "--header", root.header];
        for (const op of ops) {
            const key = HL.overrideKey(op.entry.path);
            if (op.op === "set")
                argv = argv.concat(["--set-typed", key, HL.luaType(op.entry), HL.toArg(op.entry, op.value)]);
            else
                argv = argv.concat(["--unset", key]);
        }
        return argv;
    }

    // Writes ops to shell-settings.lua now; `done(ok)` runs after the script exits.
    function _writeFile(ops, done) {
        if (ops.length === 0) {
            done?.(true);
            return;
        }
        root._run(root._configuratorArgs(ops), (code, err, startedAt) => {
            // No reload since the write started: the file may not be watched.
            if (code === 0 && root._lastReloadAt < startedAt)
                root.reloadFallback.restart();
            if (code !== 0) {
                console.warn(`[HyprlandBackend] hyprconfigurator failed (${code}): ${err.trim()}`);
                for (const op of ops) {
                    root._setOptimistic(op.entry.key, undefined);
                    root.failed(op.entry.key, "Could not save the Hyprland setting");
                }
            } else {
                for (const op of ops)
                    root.succeeded(op.entry.key);
            }
            root.listProc.running = true;
            done?.(code === 0);
        });
    }

    function _flush() {
        if (root.deferWrites)
            return;
        const ops = Object.values(root._queue);
        root._queue = {};
        root._writeFile(ops, null);
    }

    // Writes debounced changes now instead of after the debounce.
    function flush() {
        if (root.deferWrites || Object.keys(root._queue).length === 0)
            return;
        root.flushTimer.stop();
        root._flush();
    }

    function _eval(entry, value, key) {
        const expr = HL.configExpression(entry, value);
        if (expr.length === 0) {
            root.failed(key, "Invalid Hyprland option");
            return false;
        }
        root._run(["hyprctl", "eval", expr], (code, err) => {
            if (code !== 0) {
                console.warn(`[HyprlandBackend] hyprctl eval failed (${code}): ${err.trim()}`);
                root.failed(key, "Hyprland rejected the value");
            }
        });
        return true;
    }

    function snapshot(entries) {
        return entries.map(e => ({
            entry: e,
            effective: root._effective(e),
            hadOverride: HL.overrideKey(e.path) in root.overrides,
            override: root.overrides[HL.overrideKey(e.path)],
            fileTouched: false
        }));
    }

    function preview(entry, value) {
        if (!root._validEntry(entry) || !root._eval(entry, value, entry.key))
            return false;
        const live = Object.assign({}, root._live);
        live[entry.key] = { entry: entry, value: value };
        root._live = live;
        root._setOptimistic(entry.key, value);
        return true;
    }

    // Drops the override right away so the autoreload applies the base value;
    // restore() puts it back. Bypasses deferWrites on purpose.
    function previewReset(entry) {
        if (!root._validEntry(entry))
            return false;
        const live = Object.assign({}, root._live);
        delete live[entry.key];
        live[entry.key + "\u0000reset"] = { entry: entry, reset: true };
        root._live = live;
        root._setOptimistic(entry.key, undefined);
        root._writeFile([{ entry: entry, op: "unset" }], null);
        return true;
    }

    function persist(entries) {
        const ops = [];
        const live = Object.assign({}, root._live);
        for (const e of entries) {
            const item = live[e.key];
            if (item)
                ops.push({ entry: e, op: "set", value: item.value });
            delete live[e.key];
            delete live[e.key + "\u0000reset"];
        }
        root._live = live;
        root._writeFile(ops, null);
        return true;
    }

    function restore(snap) {
        const live = Object.assign({}, root._live);
        const fileOps = [];
        for (const item of snap) {
            const e = item.entry;
            const wasReset = (e.key + "\u0000reset") in live;
            delete live[e.key];
            delete live[e.key + "\u0000reset"];
            root._setOptimistic(e.key, undefined);
            if (wasReset && item.hadOverride)
                fileOps.push({ entry: e, op: "set", value: HL.fromHypr(e, item.override) });
            else if (item.effective !== undefined)
                root._eval(e, item.effective, e.key);
        }
        root._live = live;
        root._writeFile(fileOps, null);
        return true;
    }

    // Live previews are runtime state: a reload (another write, Game Mode)
    // drops them, so they are applied again while the confirmation lasts.
    function _reapplyLive() {
        for (const k in root._live) {
            const item = root._live[k];
            if (!item.reset)
                root._eval(item.entry, item.value, item.entry.key);
        }
    }

    function _run(argv, done) {
        root._jobs = root._jobs.concat([{ argv: argv, done: done }]);
        root._next();
    }

    function _next() {
        if (root.runner.running || root._jobs.length === 0)
            return;
        const job = root._jobs[0];
        root._jobs = root._jobs.slice(1);
        root.runner.done = job.done;
        root.runner.startedAt = Date.now();
        root.runner.command = job.argv;
        root.runner.running = true;
    }

    function refresh() {
        if (!root.hyprlandRunning)
            return;
        root.descriptionsProc.running = true;
        root.listProc.running = true;
        root.devicesProc.running = true;
    }

    // Tells the store which shown values changed outside a write.
    function _announce(before) {
        for (const key in root._seen) {
            const now = root._state(root._seen[key]);
            if (JSON.stringify(before[key]) !== JSON.stringify(now))
                root.succeeded(key);
        }
    }

    function _readAll() {
        const out = {};
        for (const key in root._seen)
            out[key] = root._state(root._seen[key]);
        return out;
    }

    function _state(entry) {
        return [root.read(entry), root.isModified(entry)];
    }

    onDeferWritesChanged: {
        if (!root.deferWrites && Object.keys(root._queue).length > 0)
            root.flushTimer.restart();
    }

    Component.onCompleted: root.refresh()

    readonly property Timer flushTimer: Timer {
        interval: 400
        onTriggered: root._flush()
    }

    readonly property Process runner: Process {
        property var done: null
        property real startedAt: 0
        stderr: StdioCollector { id: runnerErr }
        onExited: (exitCode, exitStatus) => {
            const done = root.runner.done;
            root.runner.done = null;
            done?.(exitCode, runnerErr.text, root.runner.startedAt);
            root._next();
        }
    }

    readonly property Timer reloadFallback: Timer {
        interval: root.reloadGraceMs
        onTriggered: root._run(["hyprctl", "reload", "config-only"], (code, err) => {
            if (code !== 0)
                console.warn(`[HyprlandBackend] hyprctl reload failed (${code}): ${err.trim()}`);
        })
    }

    readonly property Process descriptionsProc: Process {
        command: ["hyprctl", "-j", "descriptions"]
        stdout: StdioCollector { id: descriptionsOut }
        onExited: (exitCode, exitStatus) => {
            const before = root._readAll();
            try {
                if (exitCode !== 0)
                    throw new Error(`exit ${exitCode}`);
                const parsed = HL.parseDescriptions(descriptionsOut.text);
                const values = {};
                const defaults = {};
                for (const name in parsed) {
                    values[name] = parsed[name].current;
                    defaults[name] = parsed[name]["default"];
                }
                root.values = values;
                root.defaults = defaults;
                // Hyprland now reports every finished write; previews stay optimistic.
                const keep = {};
                for (const k in root._optimistic) {
                    const queued = Object.values(root._queue).some(op => op.entry.key === k);
                    if (queued || k in root._live)
                        keep[k] = root._optimistic[k];
                }
                root._optimistic = keep;
                root.loaded = true;
                root.loadError = "";
            } catch (error) {
                console.warn(`[HyprlandBackend] cannot read hyprctl -j descriptions: ${error}`);
                root.loadError = String(error);
            }
            root._announce(before);
        }
    }

    readonly property Process listProc: Process {
        command: ["python3", root.scriptPath, "--file", root.settingsFile, "--list", "--json"]
        stdout: StdioCollector { id: listOut }
        onExited: (exitCode, exitStatus) => {
            const before = root._readAll();
            try {
                if (exitCode !== 0)
                    throw new Error(`exit ${exitCode}`);
                root.overrides = JSON.parse(listOut.text);
            } catch (error) {
                console.warn(`[HyprlandBackend] cannot list ${root.settingsFile}: ${error}`);
            }
            root._announce(before);
        }
    }

    readonly property Process devicesProc: Process {
        command: ["hyprctl", "-j", "devices"]
        stdout: StdioCollector { id: devicesOut }
        onExited: (exitCode, exitStatus) => {
            try {
                root.touchpad = exitCode === 0 && HL.hasTouchpad(devicesOut.text);
            } catch (error) {
                root.touchpad = false;
            }
        }
    }

    readonly property FileView gameModeFile: FileView {
        path: root.shellOverridesFile
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.gameMode = HL.isGameModeActive(text())
        onLoadFailed: root.gameMode = false
    }

    readonly property FileView xkb: FileView {
        property var parsed: ({ layouts: [], variants: [], options: [] })
        path: "/usr/share/X11/xkb/rules/evdev.lst"
        printErrors: false
        onLoaded: root.xkb.parsed = HL.parseXkbList(text())
    }

    readonly property Connections hyprlandEvents: Connections {
        target: root.hyprlandRunning ? Hyprland : null
        function onRawEvent(event) {
            if (event.name !== "configreloaded")
                return;
            root._lastReloadAt = Date.now();
            root.reloadFallback.stop();
            // Game Mode replaces its file atomically and Hyprland reloads
            // right after, so the reload also refreshes the watch.
            root.gameModeFile.reload();
            root.refresh();
            root._reapplyLive();
        }
    }
}
