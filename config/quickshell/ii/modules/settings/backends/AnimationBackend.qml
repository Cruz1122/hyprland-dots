import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.modules.common
import qs.modules.common.functions
import qs.services
import "AnimationLogic.js" as AL
import "HyprlandLogic.js" as HL

// Hyprland animations and curves (docs/settings.md, "Backends -> animation").
//
// The managed tuples live in ~/.config/hypr/custom/shell-animations.lua,
// written only by scripts/settings/animationsgen.py (the app's only Lua
// serializer). That file is the source of truth: Hyprland forgets speed and
// curve of disabled leaves and rounds what `hyprctl -j animations` reports.
// Unmanaged cards show the dotfiles base (hyprbase.py, read once by
// HyprlandBackend and passed in as sharedBase), else Hyprland's compiled
// defaults.
//
// Writes are optimistic, debounced for 400 ms and run serially as ONE
// `animationsgen.py --apply-json - --eval` call: the generator applies the
// changed statements live with one `hyprctl eval` (curves first) and then
// writes the file. A changed file is reloaded by Hyprland's autoreload once it
// watches the file; when no `configreloaded` follows within reloadGraceMs, one
// `hyprctl reload config-only` runs instead. On any failure the live state is
// put back with a reload (the generator does it itself when eval failed, exit
// 4), the optimistic value is dropped and `failed` carries the reason.
QtObject {
    id: root

    readonly property string name: "animation"
    readonly property bool hyprlandRunning: (Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") ?? "").length > 0
    // The managed file was read (or does not exist yet).
    property bool loaded: false
    property bool foreign: false
    property string loadError: ""
    readonly property bool available: root.hyprlandRunning && root.loaded && !root.foreign
    readonly property string unavailableReason: !root.hyprlandRunning ? "Hyprland is not running"
        : root.foreign ? "custom/shell-animations.lua was not created by Settings, so it is left alone"
        : !root.loaded ? (root.loadError.length > 0 ? "Could not read the animation settings" : "Reading the animation settings…") : ""

    // HyprlandBackend.basePayload, bound by SettingsStore: the dotfiles base is
    // read in one place (guarded by Hyprland running, debounced after reloads).
    property var sharedBase: null
    // Test seam: a hyprbase.py JSON file used instead of sharedBase
    // (tests/harness/drivers/animation-backend.qml uses tests/fixtures/hyprbase-sample.json).
    property string baseFixture: ""
    // hyprbase.py result ({ curves, animations, ... }) or null while unknown.
    property var base: null
    // generator --list: card -> value, user curve name -> descriptor.
    property var managed: ({})
    property var userCurves: ({})

    property bool gameMode: false
    property bool requiresFile: false
    // Set when the first confirmed write showed Hyprland ignoring the file.
    property bool loadBroken: false
    readonly property var capabilities: root.requiresFile && !root.loadBroken ? ["animationsLoaded"] : []
    // key -> value shown by the rows.
    readonly property var values: {
        const out = {};
        for (const id of AL.CARD_IDS)
            out[`animation.${id}`] = root._shownCard(id);
        out["animation.preset"] = AL.presetFor(root._shownManaged(), root.base);
        out["animation.curves"] = root._curveList();
        return out;
    }

    property bool deferWrites: false
    readonly property bool busy: root.flushTimer.running || root._hasPending() || root._inflight !== null
        || root.runner.running || root._jobs.length > 0 || root.reloadFallback.running
    // Autoreload follows a write in well under a second (0.6 s measured).
    property int reloadGraceMs: 2000

    readonly property string generatorPath: Quickshell.shellPath("scripts/settings/animationsgen.py")
    readonly property string configDir: FileUtils.trimFileProtocol(Directories.config)
    readonly property string animationsFile: `${root.configDir}/hypr/custom/shell-animations.lua`
    readonly property string hyprlandFile: `${root.configDir}/hypr/hyprland.lua`
    readonly property string shellOverridesFile: `${root.configDir}/hypr/hyprland/shellOverrides/main.lua`

    signal succeeded(string key)
    signal failed(string key, string message)

    // Changes waiting for the debounce: { cards: {id: value|null}, curves: {name: desc|null}, removeAll, keys }.
    property var _pending: root._emptyChanges()
    // Change set being applied, shown until a managed-state read that
    // started after the generator finished (_listRun > _inflightListedAfter):
    // a read started earlier, for example by a configreloaded while the
    // generator still runs, sees the old file. -1 while the generator runs.
    property var _inflight: null
    property int _inflightListedAfter: -1
    // Managed-state reads started so far, and the number of the running one.
    property int _listRuns: 0
    property int _listRun: 0
    property bool _flushAfter: false
    // Serial queue of commands: [{ argv, stdin, done(code, stdout, stderr, startedAt) }].
    property var _jobs: []
    property real _lastReloadAt: 0
    // Confirmation against `hyprctl -j animations`, once per backend: _confirm
    // holds the managed state of the latest changed write until the check
    // ends, so a second write inside the reload grace is not judged by the
    // first one's tuples; _confirmDue waits for a reload and an idle backend.
    property bool _confirmed: false
    property var _confirm: null
    property bool _confirmDue: false
    property var _checking: null
    property bool _relist: false
    property var _seen: ({})

    function _emptyChanges() {
        return { cards: {}, curves: {}, removeAll: false, keys: [] };
    }

    function _hasPending() {
        const p = root._pending;
        return p.removeAll || Object.keys(p.cards).length > 0 || Object.keys(p.curves).length > 0;
    }

    function _kind(entry) {
        const id = AL.cardOf(entry);
        if (AL.card(id))
            return "card";
        if (id === "preset" || id === "curves")
            return id;
        return "";
    }

    function _apply(cards, curves, change) {
        if (!change)
            return;
        if (change.removeAll) {
            for (const id in cards)
                delete cards[id];
        }
        for (const id in change.cards) {
            if (change.cards[id] === null)
                delete cards[id];
            else
                cards[id] = change.cards[id];
        }
        for (const name in change.curves) {
            if (change.curves[name] === null)
                delete curves[name];
            else
                curves[name] = change.curves[name];
        }
    }

    // Managed state with the in-flight and pending changes applied.
    function _shown() {
        const cards = AL.plain(root.managed) ?? {};
        const curves = AL.plain(root.userCurves) ?? {};
        root._apply(cards, curves, root._inflight);
        root._apply(cards, curves, root._pending);
        return { cards: cards, curves: curves };
    }

    function _shownManaged() {
        return root._shown().cards;
    }

    function _shownCard(id) {
        return AL.cardValue(id, root._shownManaged(), root.base);
    }

    function _curveList() {
        const curves = root._shown().curves;
        return Object.keys(curves).sort().map(name => Object.assign({ name: name }, curves[name]));
    }

    function _catalog() {
        return AL.curveCatalog(root.base, root._shown().curves);
    }

    function _note(entry) {
        if (!root._seen[entry.key])
            root._seen[entry.key] = entry;
    }

    // ------------------------------------------------------------ contract

    function read(entry) {
        root._note(entry);
        const kind = root._kind(entry);
        if (kind === "card")
            return root._shownCard(AL.cardOf(entry));
        if (kind === "preset")
            return AL.presetFor(root._shownManaged(), root.base);
        if (kind === "curves")
            return root._curveList();
        return undefined;
    }

    // The dotfiles base value; undefined while the base is unknown.
    function defaultValue(entry) {
        const kind = root._kind(entry);
        if (kind === "card")
            return AL.baseCard(AL.cardOf(entry), root.base);
        if (kind === "preset")
            return "default";
        if (kind === "curves")
            return [];
        return undefined;
    }

    // A card is modified while the generated file holds its line. The preset
    // is derived and the curve library has no default, so neither ever is
    // (a "Reset page" must not delete the user's curves).
    function isModified(entry) {
        return root._kind(entry) === "card" && AL.cardOf(entry) in root._shownManaged();
    }

    function statusNote(entry) {
        const kind = root._kind(entry);
        return root.gameMode && (kind === "card" || kind === "preset") ? "Paused by Game Mode" : "";
    }

    function write(entry, value) {
        const kind = root._kind(entry);
        if (kind === "card")
            return root._writeCard(entry, value);
        if (kind === "preset")
            return root._writePreset(entry, value);
        if (kind === "curves")
            return root._writeCurves(entry, value);
        root.failed(entry.key, "Unknown animation");
        return false;
    }

    function reset(entry) {
        const kind = root._kind(entry);
        if (kind === "card") {
            const id = AL.cardOf(entry);
            if (!(id in root._shownManaged()))
                return true;
            root._queue(entry.key, c => { c.cards[id] = null; });
            return true;
        }
        if (kind === "preset")
            return root._writePreset(entry, "default");
        return true;
    }

    // Animation entries are never risky; these keep the backend contract.
    function snapshot(entries) {
        return entries.map(e => ({ entry: e, value: root.read(e), managed: root.isModified(e) }));
    }

    function preview(entry, value) {
        return false;
    }

    function persist(entries) {
        return true;
    }

    function restore(snap) {
        for (const item of snap) {
            if (root._kind(item.entry) === "card" && !item.managed)
                root.reset(item.entry);
            else if (item.value !== undefined)
                root.write(item.entry, item.value);
        }
        return true;
    }

    function flush() {
        if (root.deferWrites || !root._hasPending())
            return;
        root.flushTimer.stop();
        root._flush();
    }

    // ---------------------------------------------------------- UI helpers

    function curveCatalog() {
        return root._catalog();
    }

    function styleOptions(card) {
        return AL.styleOptions(card);
    }

    function presets() {
        return AL.presets();
    }

    // Card ids whose shown value uses the curve (a used curve cannot be deleted).
    function curveUsage(name) {
        return AL.curveUsage(name, root._shownManaged(), root.base);
    }

    function summaryParts(card) {
        return AL.summaryParts(card, root._shownCard(card), root._catalog());
    }

    // -------------------------------------------------------------- writes

    function _writeCard(entry, value) {
        const id = AL.cardOf(entry);
        const checked = AL.validateCard(id, value, root._catalog());
        if (!checked.ok) {
            root.failed(entry.key, checked.error);
            return false;
        }
        if (!root.base) {
            root.failed(entry.key, "The dotfiles animations could not be read, so they cannot be changed yet");
            return false;
        }
        if (AL.equal(checked.value, root._shownCard(id)))
            return true;
        root._queue(entry.key, c => { c.cards[id] = checked.value; });
        return true;
    }

    // One transaction for the 10 cards: one generator call, one eval and at
    // most one reload. "default" removes every animation line, keeping curves.
    function _writePreset(entry, value) {
        if (AL.PRESET_IDS.indexOf(value) < 0) {
            root.failed(entry.key, "Unknown preset");
            return false;
        }
        const shown = root._shownManaged();
        if (value === "default") {
            if (Object.keys(shown).length === 0)
                return true;
            root._queue(entry.key, c => {
                c.cards = {};
                c.removeAll = true;
            });
            return true;
        }
        const cards = AL.presetCards(value, root.base);
        if (!cards) {
            root.failed(entry.key, "Presets need the dotfiles animations, which could not be read");
            return false;
        }
        if (AL.CARD_IDS.every(id => id in shown && AL.equal(shown[id], cards[id])))
            return true;
        root._queue(entry.key, c => {
            for (const id of AL.CARD_IDS)
                c.cards[id] = cards[id];
        });
        return true;
    }

    // The value is the whole list of user curves: added, changed and removed
    // curves become one change set. A curve an animation uses cannot go.
    function _writeCurves(entry, value) {
        if (!Array.isArray(value)) {
            root.failed(entry.key, "Invalid list of curves");
            return false;
        }
        const current = root._shown().curves;
        const wanted = {};
        for (const item of value) {
            const name = item?.name;
            const checked = AL.validateCurve(name, item);
            if (!checked.ok || name in wanted) {
                root.failed(entry.key, checked.ok ? "Invalid list of curves" : checked.error);
                return false;
            }
            wanted[name] = checked.value;
        }
        const changes = {};
        for (const name in current) {
            if (name in wanted)
                continue;
            if (root.curveUsage(name).length > 0) {
                root.failed(entry.key, "This curve is still used by an animation");
                return false;
            }
            changes[name] = null;
        }
        for (const name in wanted) {
            const old = current[name];
            if (!old || !AL.equal(AL.validateCurve(name, old).value ?? old, wanted[name]))
                changes[name] = wanted[name];
        }
        if (Object.keys(changes).length === 0)
            return true;
        root._queue(entry.key, c => Object.assign(c.curves, changes));
        return true;
    }

    function _queue(key, mutate) {
        const next = AL.plain(root._pending);
        mutate(next);
        if (next.keys.indexOf(key) < 0)
            next.keys.push(key);
        root._pending = next;
        if (!root.deferWrites)
            root.flushTimer.restart();
    }

    function _flush() {
        if (root.deferWrites || !root._hasPending())
            return;
        if (root._inflight !== null) {
            root._flushAfter = true;
            return;
        }
        const change = root._pending;
        root._pending = root._emptyChanges();
        root._inflight = change;
        root._inflightListedAfter = -1;
        const payload = { cards: change.cards, curves: change.curves, removeAllAnimations: change.removeAll };
        if (root.base)
            payload.base = root.base;
        const argv = ["python3", root.generatorPath, "--file", root.animationsFile, "--apply-json", "-", "--eval"];
        root._run(argv, JSON.stringify(payload), (code, out, err, startedAt) => root._applied(change, code, out, err, startedAt));
    }

    function _applied(change, code, out, err, startedAt) {
        let result = null;
        try {
            result = JSON.parse(out);
        } catch (error) {
            result = null;
        }
        if (code === 0 && result?.ok) {
            if (result.changed) {
                // No reload since the write started: the file may not be watched.
                if (root._lastReloadAt < startedAt)
                    root.reloadFallback.restart();
                if (!root._confirmed && Object.keys(result.cards ?? {}).length > 0) {
                    const keys = (root._confirm?.keys ?? []).filter(key => change.keys.indexOf(key) < 0);
                    root._confirm = { cards: result.cards, keys: keys.concat(change.keys) };
                }
            }
            for (const key of change.keys)
                root.succeeded(key);
            root._inflightListedAfter = root._listRuns;
            root._list();
            return;
        }
        // Exit 4: the generator already reloaded. Anything else may have left
        // a partly applied eval behind, so the files are reloaded here.
        if (code !== 4)
            root._run(["hyprctl", "reload", "config-only"], null, (reloadCode, reloadOut, reloadErr) => {
                if (reloadCode !== 0)
                    console.warn(`[AnimationBackend] hyprctl reload failed (${reloadCode}): ${reloadErr.trim()}`);
            });
        const detail = (result?.errors ?? []).join("; ") || err.trim() || `exit ${code}`;
        console.warn(`[AnimationBackend] animationsgen.py failed (${code}): ${detail}`);
        root._inflight = null;
        const message = Translation.tr("Could not apply the animation: %1").arg(detail);
        for (const key of change.keys)
            root.failed(key, message);
        root._list();
    }

    function _run(argv, stdin, done) {
        root._jobs = root._jobs.concat([{ argv: argv, stdin: stdin, done: done }]);
        root._next();
    }

    function _next() {
        if (root.runner.running || root._jobs.length === 0)
            return;
        const job = root._jobs[0];
        root._jobs = root._jobs.slice(1);
        root.runner.done = job.done;
        root.runner.stdinText = job.stdin;
        root.runner.startedAt = Date.now();
        root.runner.command = job.argv;
        root.runner.stdinEnabled = job.stdin !== null;
        root.runner.running = true;
    }

    // --------------------------------------------------------------- reads

    function _list() {
        if (!root.hyprlandRunning)
            return;
        if (root.listProc.running) {
            root._relist = true;
            return;
        }
        root._listRun = ++root._listRuns;
        root.listProc.running = true;
    }

    // sharedBase follows reloads by itself; only the test fixture is re-read.
    function _readBase() {
        if (root.baseFixture.length > 0)
            root.baseFixtureFile.reload();
    }

    function _setBase(parsed) {
        root.base = parsed && parsed.ok !== false && typeof parsed.animations === "object" ? parsed : null;
    }

    // Everything a row shows: rows learn about changes only through
    // succeeded(key), also when only the default (the base arrived) or the
    // status note (Game Mode) changed.
    function _readAll() {
        const out = {};
        for (const key in root._seen) {
            const entry = root._seen[key];
            out[key] = JSON.stringify([root.read(entry), root.isModified(entry), root.defaultValue(entry), root.statusNote(entry)]);
        }
        return out;
    }

    // Tells the store which shown values changed outside a write.
    function _announce(before) {
        const now = root._readAll();
        for (const key in now) {
            if (before[key] !== now[key])
                root.succeeded(key);
        }
    }

    // Game Mode changes only the status notes; nothing else announces them.
    function _setGameMode(active) {
        const before = root._readAll();
        root.gameMode = active;
        root._announce(before);
    }

    function _setRequiresFile(requires) {
        const before = root._readAll();
        root.requiresFile = requires;
        root._announce(before);
    }

    // A reload happened (Hyprland's event, or our fallback finished): check
    // once that Hyprland now reports the tuples of the latest changed write.
    function _reloaded() {
        if (root._confirm && !root._confirmed) {
            root._confirmDue = true;
            root._checkLoaded();
        }
    }

    // A queued, running or not yet reloaded write would change what -j
    // animations reports, so the check waits until the backend is idle.
    function _checkLoaded() {
        if (!root._confirmDue || root._confirmed || !root._confirm || root.busy || root.animationsProc.running)
            return;
        root._confirmDue = false;
        root._checking = root._confirm;
        root.animationsProc.running = true;
    }

    onBusyChanged: root._checkLoaded()

    onDeferWritesChanged: {
        if (!root.deferWrites && root._hasPending())
            root.flushTimer.restart();
    }

    // The FileViews load by themselves; sharedBase arrives through its binding.
    Component.onCompleted: {
        if (root.baseFixture.length === 0 && root.sharedBase)
            root._setBase(root.sharedBase);
        root._list();
    }

    readonly property Timer flushTimer: Timer {
        interval: 400
        onTriggered: root._flush()
    }

    readonly property Process runner: Process {
        property var done: null
        property var stdinText: null
        property real startedAt: 0
        stdout: StdioCollector { id: runnerOut }
        stderr: StdioCollector { id: runnerErr }
        onRunningChanged: {
            if (root.runner.running && root.runner.stdinText !== null) {
                root.runner.write(root.runner.stdinText);
                root.runner.stdinEnabled = false;
            }
        }
        onExited: (exitCode, exitStatus) => {
            const done = root.runner.done;
            root.runner.done = null;
            root.runner.stdinText = null;
            done?.(exitCode, runnerOut.text, runnerErr.text, root.runner.startedAt);
            root._next();
        }
    }

    readonly property Timer reloadFallback: Timer {
        interval: root.reloadGraceMs
        onTriggered: root._run(["hyprctl", "reload", "config-only"], null, (code, out, err) => {
            if (code !== 0)
                console.warn(`[AnimationBackend] hyprctl reload failed (${code}): ${err.trim()}`);
            else
                root._reloaded();
        })
    }

    readonly property Process listProc: Process {
        command: ["python3", root.generatorPath, "--file", root.animationsFile, "--list", "--json"]
        stdout: StdioCollector { id: listOut }
        stderr: StdioCollector { id: listErr }
        onExited: (exitCode, exitStatus) => {
            const before = root._readAll();
            try {
                const data = JSON.parse(listOut.text);
                root.foreign = exitCode === 3;
                if (exitCode !== 0 && exitCode !== 3)
                    throw new Error(`exit ${exitCode}: ${(data.errors ?? []).join("; ")}`);
                if (exitCode === 0) {
                    root.managed = data.cards ?? {};
                    root.userCurves = data.curves ?? {};
                    if ((data.errors ?? []).length > 0)
                        console.warn(`[AnimationBackend] ${root.animationsFile}: ${data.errors.join("; ")}`);
                }
                root.loaded = true;
                root.loadError = "";
            } catch (error) {
                console.warn(`[AnimationBackend] cannot list ${root.animationsFile}: ${error} ${listErr.text.trim()}`);
                root.loadError = String(error);
            }
            // The written change is part of the managed state once a read
            // that started after the write ends.
            if (root._inflight !== null && root._inflightListedAfter >= 0 && root._listRun > root._inflightListedAfter)
                root._inflight = null;
            root._announce(before);
            if (root._relist) {
                root._relist = false;
                root._list();
            } else if (root._flushAfter && root._inflight === null) {
                root._flushAfter = false;
                if (!root.flushTimer.running)
                    root._flush();
            }
        }
    }

    readonly property Process animationsProc: Process {
        command: ["hyprctl", "-j", "animations"]
        stdout: StdioCollector { id: animationsOut }
        onExited: (exitCode, exitStatus) => {
            const confirm = root._checking;
            root._checking = null;
            if (!confirm || root._confirmed)
                return;
            // Another write landed during the read: judge it after its reload.
            if (root._confirm !== confirm || root.busy) {
                root._confirmDue = true;
                root._checkLoaded();
                return;
            }
            // Only a parsed answer can show that Hyprland ignored the file; a
            // failed read is tried again after the next reload.
            if (exitCode !== 0 || AL.animationList(animationsOut.text) === null) {
                console.warn(`[AnimationBackend] cannot read hyprctl -j animations (${exitCode}); checking again after the next reload`);
                return;
            }
            root._confirmed = true;
            root._confirm = null;
            const mismatches = AL.loadedMismatches(animationsOut.text, confirm.cards, root._catalog());
            if (mismatches.length === 0)
                return;
            console.warn(`[AnimationBackend] Hyprland does not report the written animations: ${mismatches.join(", ")}`);
            root.loadBroken = true;
            for (const key of confirm.keys)
                root.failed(key, "Hyprland did not load the animation settings: update hyprland.lua");
        }
    }

    onSharedBaseChanged: {
        if (root.baseFixture.length > 0)
            return;
        const before = root._readAll();
        root._setBase(root.sharedBase);
        root._announce(before);
    }

    readonly property FileView baseFixtureFile: FileView {
        path: root.baseFixture
        printErrors: false
        onLoaded: {
            const before = root._readAll();
            try {
                root._setBase(JSON.parse(text()));
            } catch (error) {
                console.warn(`[AnimationBackend] invalid base fixture ${root.baseFixture}: ${error}`);
                root.base = null;
            }
            root._announce(before);
        }
        onLoadFailed: {
            if (root.baseFixture.length === 0)
                return;
            const before = root._readAll();
            root.base = null;
            root._announce(before);
        }
    }

    readonly property FileView hyprlandConfig: FileView {
        path: root.hyprlandFile
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root._setRequiresFile(AL.requiresAnimations(text()))
        onLoadFailed: root._setRequiresFile(false)
    }

    readonly property FileView gameModeFile: FileView {
        path: root.shellOverridesFile
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root._setGameMode(HL.isGameModeActive(text()))
        onLoadFailed: root._setGameMode(false)
    }

    readonly property Connections hyprlandEvents: Connections {
        target: root.hyprlandRunning ? Hyprland : null
        function onRawEvent(event) {
            if (event.name !== "configreloaded")
                return;
            root._lastReloadAt = Date.now();
            root.reloadFallback.stop();
            // Game Mode replaces its file atomically and Hyprland reloads
            // right after, so the reload also refreshes the watches.
            root.gameModeFile.reload();
            root.hyprlandConfig.reload();
            root._readBase();
            root._list();
            root._reloaded();
        }
    }
}
