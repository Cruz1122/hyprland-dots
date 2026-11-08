import QtQuick
import "SettingsLogic.js" as Logic

// Store logic behind the SettingsStore singleton. It only depends on QtQuick
// so tests/qml_settings can drive it with a mock registry and mock backends.
//
// registry: object with entry(key) and entriesForPage(pageId).
// backends: { <backend name>: backend } (interface in docs/settings.md).
QtObject {
    id: root

    property var registry: null
    property var backends: ({})
    property int confirmSeconds: Logic.CONFIRM_SECONDS
    // null or { keys, secondsLeft }; replaced (never mutated) on every change.
    property var pendingConfirmation: null
    property int revision: 0

    signal committed(string key)
    signal failed(string key, string message)

    // Snapshots of the pending risky batch, oldest first: [{ key, backend, snapshot }].
    property var _snapshots: []
    property var _connected: []

    readonly property Timer _countdown: Timer {
        interval: 1000
        repeat: true
        running: root.pendingConfirmation !== null
        onTriggered: {
            const next = Logic.tickBatch(root.pendingConfirmation);
            if (next.expired)
                root.revert();
            else
                root.pendingConfirmation = next.pending;
        }
    }

    function entry(key) {
        return root.registry ? root.registry.entry(key) : null;
    }

    function backendFor(entry) {
        if (!entry || !Logic.isWritable(entry))
            return null;
        return root.backends[entry.backend] ?? null;
    }

    function value(key) {
        void root.revision;
        const e = root.entry(key);
        const b = root.backendFor(e);
        return b ? Logic.toPlain(b.read(e)) : undefined;
    }

    function defaultValue(key) {
        const e = root.entry(key);
        const b = root.backendFor(e);
        return b ? Logic.toPlain(b.defaultValue(e)) : undefined;
    }

    function isModified(key) {
        void root.revision;
        const e = root.entry(key);
        const b = root.backendFor(e);
        return !!b && b.available && b.isModified(e);
    }

    function isAvailable(key) {
        const e = root.entry(key);
        if (!e)
            return false;
        if (!Logic.isWritable(e))
            return true;
        const b = root.backendFor(e);
        return !!b && b.available;
    }

    function unavailableReason(key) {
        const e = root.entry(key);
        if (!e)
            return "Unknown setting";
        if (root.isAvailable(key))
            return "";
        const b = root.backendFor(e);
        return b ? (b.unavailableReason || "Not available") : "Not available";
    }

    // Optional backend hook statusNote(entry): an English source string about
    // the row's current state (for example "Paused by Game Mode"), or "".
    function statusNote(key) {
        void root.revision;
        const e = root.entry(key);
        const b = root.backendFor(e);
        if (!b || !b.available || typeof b.statusNote !== "function")
            return "";
        const note = b.statusNote(e);
        return typeof note === "string" ? note : "";
    }

    function hasCapability(name) {
        for (const backendName in root.backends) {
            const b = root.backends[backendName];
            const caps = b?.capabilities ?? [];
            if (b?.available && (Logic.isArrayLike(caps) ? Array.from(caps).includes(name) : !!caps[name]))
                return true;
        }
        return false;
    }

    function isEnabled(key) {
        const e = root.entry(key);
        return !!e && root.isAvailable(key) && Logic.evalCondition(e.enabledWhen, k => root.value(k), c => root.hasCapability(c));
    }

    function isVisible(key) {
        const e = root.entry(key);
        return !!e && Logic.evalCondition(e.visibleWhen, k => root.value(k), c => root.hasCapability(c));
    }

    // Leaf condition that keeps an entry disabled ({ key, ... } or
    // { capability }), or null when the condition holds.
    function blockingCondition(key) {
        const e = root.entry(key);
        if (!e)
            return null;
        return Logic.blockingCondition(e.enabledWhen, k => root.value(k), c => root.hasCapability(c));
    }

    function _fail(key, message) {
        root.failed(key, message);
        return false;
    }

    function _uniqueOthers(e) {
        const group = e.validate?.unique;
        if (!group || !root.registry?.allEntries)
            return [];
        return root.registry.allEntries()
            .filter(other => other.key !== e.key && other.validate?.unique === group)
            .map(other => ({ key: other.key, value: root.value(other.key) }));
    }

    // Validates, coerces and routes a user change. Returns false (and emits
    // failed) when the change is rejected; the caller resyncs its control.
    function write(key, rawValue) {
        const e = root.entry(key);
        if (!e)
            return root._fail(key, "Unknown setting");
        const b = root.backendFor(e);
        if (!b)
            return root._fail(key, "This setting cannot be changed here");
        if (!b.available)
            return root._fail(key, b.unavailableReason || "Not available");
        if (!Logic.evalCondition(e.enabledWhen, k => root.value(k), c => root.hasCapability(c)))
            return root._fail(key, "This setting is disabled");
        const result = Logic.coerce(e, rawValue);
        if (!result.ok)
            return root._fail(key, result.error);
        const clash = Logic.uniqueConflict(e, result.value, root._uniqueOthers(e));
        if (clash)
            return root._fail(key, "Already used by another setting");
        if (Logic.deepEqual(result.value, root.value(key)))
            return true;
        if (e.risky)
            return root._preview(e, b, result.value);
        if (b.write(e, result.value) === false)
            return root._fail(key, "Could not save the change");
        root.revision++;
        return true;
    }

    // Backends that declare `deferWrites` hold their normal writes while a
    // risky batch is pending (for example, a Hyprland file write would
    // trigger an autoreload that drops a live monitor preview).
    function _setDeferWrites(on) {
        for (const name in root.backends) {
            const b = root.backends[name];
            if (b && "deferWrites" in b)
                b.deferWrites = on;
        }
    }

    function _preview(e, b, value) {
        return root._joinRisky(e, b, () => b.preview(e, value));
    }

    // Snapshots the entry (once per batch), applies `apply` live and joins
    // the pending batch, restarting the countdown.
    function _joinRisky(e, b, apply) {
        const first = root.pendingConfirmation === null;
        const inBatch = root._snapshots.some(s => s.key === e.key);
        if (!inBatch)
            root._snapshots = root._snapshots.concat([{ key: e.key, entry: e, backend: b, snapshot: b.snapshot([e]) }]);
        if (first)
            root._setDeferWrites(true);
        if (apply() === false) {
            if (!inBatch)
                root._snapshots = root._snapshots.filter(s => s.key !== e.key);
            if (first)
                root._setDeferWrites(false);
            return root._fail(e.key, "Could not apply the change");
        }
        root.pendingConfirmation = Logic.joinBatch(root.pendingConfirmation, [e.key], root.confirmSeconds);
        root.revision++;
        return true;
    }

    function reset(key) {
        const e = root.entry(key);
        const b = root.backendFor(e);
        if (!b)
            return root._fail(key, "This setting cannot be changed here");
        if (!b.available)
            return root._fail(key, b.unavailableReason || "Not available");
        // A backend whose reset has no known value up front (Hyprland drops
        // the override) previews the reset itself.
        if (e.risky && typeof b.previewReset === "function")
            return root._joinRisky(e, b, () => b.previewReset(e));
        if (e.risky)
            return root.write(key, root.defaultValue(key));
        if (b.reset(e) === false)
            return root._fail(key, "Could not reset the setting");
        root.revision++;
        return true;
    }

    // Resets every modified, available entry shown on the page (aliases too).
    // Keys "Reset page" acts on: modified, available keys of the rows the
    // page shows. Hidden rows (visibleWhen) are left alone, since the user
    // cannot see what would change.
    function _resettableKeys(pageId) {
        const out = [];
        for (const e of (root.registry?.entriesForPage(pageId) ?? [])) {
            if (!root.isVisible(e.key))
                continue;
            const keys = e.type === "custom" && e.keys ? e.keys : [e.key];
            if (keys.some(k => root.isAvailable(k) && root.isModified(k)))
                out.push(...keys.filter(k => !out.includes(k) && root.isAvailable(k) && root.isModified(k)));
        }
        return out;
    }

    // Number of visible rows on the page with at least one modified key.
    function modifiedCount(pageId) {
        void root.revision;
        let count = 0;
        for (const e of (root.registry?.entriesForPage(pageId) ?? [])) {
            const keys = e.type === "custom" && e.keys ? e.keys : [e.key];
            if (root.isVisible(e.key) && keys.some(k => root.isModified(k)))
                count++;
        }
        return count;
    }

    function resetPage(pageId) {
        let ok = true;
        for (const key of root._resettableKeys(pageId))
            ok = root.reset(key) && ok;
        return ok;
    }

    function _persistByBackend(snapshots) {
        const groups = [];
        for (const s of snapshots) {
            let g = groups.find(x => x.backend === s.backend);
            if (!g) {
                g = { backend: s.backend, entries: [] };
                groups.push(g);
            }
            g.entries.push(s.entry);
        }
        return groups;
    }

    function confirm() {
        if (!root.pendingConfirmation)
            return;
        const snapshots = root._snapshots;
        root._snapshots = [];
        root.pendingConfirmation = null;
        for (const g of root._persistByBackend(snapshots)) {
            if (g.backend.persist(g.entries) === false) {
                for (const e of g.entries)
                    root.failed(e.key, "Could not save the change");
            }
        }
        root._setDeferWrites(false);
        root.revision++;
    }

    function revert() {
        const snapshots = root._snapshots;
        root._snapshots = [];
        root.pendingConfirmation = null;
        for (let i = snapshots.length - 1; i >= 0; i--) {
            if (snapshots[i].backend.restore(snapshots[i].snapshot) === false)
                root.failed(snapshots[i].key, "Could not restore the previous value");
        }
        if (snapshots.length > 0)
            root._setDeferWrites(false);
        if (snapshots.length > 0)
            root.revision++;
    }

    // ------------------------------------------------------------ shutdown

    // Names of backends with work queued or running (`busy`, optional).
    function busyBackends() {
        const out = [];
        for (const name in root.backends) {
            if (root.backends[name]?.busy === true)
                out.push(name);
        }
        return out;
    }

    // Ends the session before quitting: reverts a pending risky batch (its
    // restores are asynchronous), runs debounced writes now (`flush`,
    // optional) and calls `done` once no backend is busy, or after
    // `timeoutMs` so a stuck command cannot keep the process alive.
    function finish(done, timeoutMs) {
        if (root.pendingConfirmation)
            root.revert();
        for (const name in root.backends) {
            const b = root.backends[name];
            if (typeof b?.flush === "function")
                b.flush();
        }
        root._finishDone = done;
        root._finishDeadline = Date.now() + (timeoutMs ?? Logic.FINISH_TIMEOUT_MS);
        root._finishPoll.restart();
    }

    // Keeps the session going (the window was opened again).
    function cancelFinish() {
        root._finishPoll.stop();
        root._finishDone = null;
    }

    property var _finishDone: null
    property real _finishDeadline: 0

    readonly property Timer _finishPoll: Timer {
        interval: 50
        repeat: true
        onTriggered: {
            const busy = root.busyBackends();
            if (busy.length > 0 && Date.now() < root._finishDeadline)
                return;
            if (busy.length > 0)
                console.warn(`[SettingsStore] quitting before these finished: ${busy.join(", ")}`);
            root._finishPoll.stop();
            const done = root._finishDone;
            root._finishDone = null;
            done?.();
        }
    }

    function _onSucceeded(key) {
        root.revision++;
        root.committed(key);
    }

    function _onFailed(key, message) {
        root.revision++;
        root.failed(key, message);
    }

    function _connectBackends() {
        for (const name in root.backends) {
            const b = root.backends[name];
            if (!b || root._connected.includes(b))
                continue;
            b.succeeded.connect(root._onSucceeded);
            b.failed.connect(root._onFailed);
            root._connected.push(b);
        }
    }

    onBackendsChanged: root._connectBackends()
    Component.onCompleted: root._connectBackends()
}
