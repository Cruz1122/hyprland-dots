//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
//@ pragma Env QT_QUICK_FLICKABLE_WHEEL_DECELERATION=10000
//@ pragma Env QT_SCALE_FACTOR=1

// Interaction driver for the settings app, run inside the harness sandbox:
//   scripts/settings-harness/run.sh --driver tests/harness/settings-interact.qml --allow-config-writes
//
// (a) Search: accented and unaccented queries return the same results, and
//     activating the first result opens its page and highlights the row.
// (b) Every visible, enabled `config` entry of type bool or enum: the row's
//     primary interaction (row.interact()) writes config.json, changing only
//     that key; restoring it brings the file back to the original value.
// Results are "[harness:report]" lines; any failure is a "fatal" event.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
// @harness-imports

ShellRoot {
    id: root

    property var win: null
    property var steps: []
    property int stepIndex: 0
    property int failures: 0
    readonly property var searchPairs: [["atenuación", "atenuacion"], ["acción", "accion"]]

    function report(payload) {
        console.info(`[harness:report] ${JSON.stringify(payload)}`);
    }

    function fail(message) {
        root.failures++;
        root.report({ type: "fatal", message: message });
    }

    function findItem(item, name) {
        if (!item)
            return null;
        if (item.objectName === name)
            return item;
        for (const child of item.children) {
            const found = root.findItem(child, name);
            if (found)
                return found;
        }
        return null;
    }

    function readConfig() {
        const view = fileComponent.createObject(root, { path: Directories.shellConfigPath });
        const text = view.text();
        view.destroy();
        return text;
    }

    function flatten(value, prefix, out) {
        if (value !== null && typeof value === "object" && !Array.isArray(value)) {
            for (const key in value)
                root.flatten(value[key], prefix ? `${prefix}.${key}` : key, out);
        } else {
            out[prefix] = JSON.stringify(value);
        }
        return out;
    }

    // Keys whose value differs. Keys absent from `before` are ignored: the
    // first write adds every schema default the seeded file lacks.
    function changedKeys(beforeText, afterText) {
        const before = root.flatten(JSON.parse(beforeText), "", {});
        const after = root.flatten(JSON.parse(afterText), "", {});
        const changed = [];
        for (const key in before) {
            if (!(key in after) || after[key] !== before[key])
                changed.push(key);
        }
        return changed;
    }

    // Leaf paths of a config path (list values flatten to one key, objects to many).
    function touches(changed, path) {
        return changed.length > 0 && changed.every(k => k === path || k.startsWith(path + "."));
    }

    // Polls `check` every 100 ms up to `timeoutMs`, then calls done(ok).
    function waitFor(check, timeoutMs, done) {
        const timer = pollComponent.createObject(root, { deadline: Date.now() + timeoutMs, check: check, done: done });
        timer.start();
    }

    // Screenshot of one item for review (SHOT_DIR is the run's output directory).
    function saveShot(item, name, then) {
        const dir = Quickshell.env("SHOT_DIR");
        const started = !!dir && item.grabToImage(result => {
            result.saveToFile(`${dir}/${name}.png`);
            if (then)
                then();
        });
        if (!started && then)
            then();
    }

    function openPage(pageId) {
        const index = root.win.pages.findIndex(p => p.id === pageId);
        root.win.currentPage = index;
        return index >= 0;
    }

    function rowFor(key) {
        return root.findItem(root.win.contentItem, "row:" + key);
    }

    // ---------------------------------------------------------------- search

    function searchStep() {
        const nav = root.findItem(root.win.contentItem, "settingsNavigation");
        if (!nav) {
            root.fail("navigation not found");
            root.next();
            return;
        }
        let target = null;
        for (const [accented, plain] of root.searchPairs) {
            nav.setQuery(accented);
            const a = JSON.stringify(nav.results);
            nav.setQuery(plain);
            const b = JSON.stringify(nav.results);
            root.report({ type: "search", query: accented, plain: plain, results: nav.results.length, same: a === b });
            if (a !== b)
                root.fail(`search "${accented}" and "${plain}" differ`);
            const entry = nav.results.find(r => r.kind === "entry");
            if (!target && entry)
                target = { query: plain, result: entry };
        }
        if (!target) {
            root.fail("no search pair found an entry");
            nav.clearSearch();
            root.next();
            return;
        }
        nav.setQuery(target.query);
        // Let the results list lay out before the screenshot and activation.
        root.waitFor(() => false, 400, () => root.saveShot(nav, "search-results", () => root.activateTarget(nav, target)));
    }

    function activateTarget(nav, target) {
        nav.activateResult(nav.results.indexOf(nav.results.find(r => r.key === target.result.key)));
        root.waitFor(() => {
            const row = root.rowFor(target.result.key);
            return root.win.pages[root.win.currentPage]?.id === target.result.pageId && row?.visible && row.highlighted;
        }, 4000, ok => {
            root.report({ type: "reveal", key: target.result.key, ok: ok });
            if (ok)
                root.saveShot(root.rowFor(target.result.key), "revealed-row");
            if (!ok)
                root.fail(`activating the result for ${target.result.key} did not reveal and highlight the row`);
            root.next();
        });
    }

    // ---------------------------------------------------------- interactions

    function interactionSteps() {
        const steps = [];
        for (const page of root.win.pages) {
            for (const entry of SettingsRegistry.entriesForPage(page.id)) {
                if (entry.aliasOf || entry.backend !== "config" || (entry.type !== "bool" && entry.type !== "enum"))
                    continue;
                steps.push({ pageId: page.id, entry: entry });
            }
        }
        return steps;
    }

    function interactStep(step) {
        const key = step.entry.key;
        if (!SettingsStore.isVisible(key) || !SettingsStore.isEnabled(key)) {
            root.report({ type: "interact", key: key, skipped: "hidden or disabled" });
            root.next();
            return;
        }
        root.openPage(step.pageId);
        root.waitFor(() => root.win.pageReady && !!root.rowFor(key), 4000, ready => {
            const row = root.rowFor(key);
            if (!ready || !row) {
                root.fail(`${key}: row not found on ${step.pageId}`);
                root.next();
                return;
            }
            const original = root.readConfig();
            const originalValue = SettingsStore.value(key);
            if (!row.interact()) {
                root.fail(`${key}: row.interact() did nothing`);
                root.next();
                return;
            }
            if (SettingsStore.pendingConfirmation)
                SettingsStore.confirm();
            root.waitFor(() => root.readConfig() !== original, 4000, written => {
                const after = root.readConfig();
                const changed = written ? root.changedKeys(original, after) : [];
                if (!written || !root.touches(changed, step.entry.path))
                    root.fail(`${key}: expected only ${step.entry.path} to change, got ${JSON.stringify(changed)}`);
                root.restore(step, original, originalValue, after);
            });
        });
    }

    function restore(step, original, originalValue, changedText) {
        const key = step.entry.key;
        const viaReset = JSON.stringify(originalValue) === JSON.stringify(SettingsStore.defaultValue(key));
        const row = root.rowFor(key);
        if (viaReset && row)
            row.resetToDefault();
        else
            SettingsStore.write(key, originalValue);
        if (SettingsStore.pendingConfirmation)
            SettingsStore.confirm();
        root.waitFor(() => root.readConfig() !== changedText, 4000, written => {
            const back = root.changedKeys(original, root.readConfig());
            const ok = written && back.length === 0;
            root.report({ type: "interact", key: key, restoredBy: viaReset ? "reset" : "write", ok: ok });
            if (!ok)
                root.fail(`${key}: restoring left ${JSON.stringify(back)} changed`);
            root.next();
        });
    }

    // ------------------------------------------------------------------ flow

    function next() {
        if (root.stepIndex >= root.steps.length) {
            root.report({ type: "done", failures: root.failures });
            Qt.quit();
            return;
        }
        const step = root.steps[root.stepIndex++];
        root.report({ type: "visit", size: `${root.win.width}x${root.win.height}`, name: step.pageId ?? "search" });
        if (step.kind === "search")
            root.searchStep();
        else
            root.interactStep(step);
    }

    function start() {
        root.steps = [{ kind: "search" }].concat(root.interactionSteps());
        root.report({ type: "start", steps: root.steps.length });
        root.next();
    }

    Component.onCompleted: {
        const component = Qt.createComponent(Qt.resolvedUrl("settings.qml"));
        if (component.status !== Component.Ready) {
            root.fail(`settings.qml failed to load: ${component.errorString()}`);
            Qt.callLater(Qt.quit);
            return;
        }
        root.win = component.createObject(root, { width: 1100, height: 760 });
    }

    Component {
        id: fileComponent
        FileView {
            blockLoading: true
            printErrors: false
        }
    }

    Component {
        id: pollComponent
        Timer {
            id: poll
            property real deadline: 0
            property var check: null
            property var done: null
            interval: 100
            repeat: true
            onTriggered: {
                const ok = poll.check();
                if (ok || Date.now() > poll.deadline) {
                    poll.stop();
                    const done = poll.done;
                    poll.destroy();
                    done(ok);
                }
            }
        }
    }

    // Waits for the config file so interactions start from persisted values.
    Timer {
        interval: 100
        repeat: true
        running: true
        property int waited: 0
        onTriggered: {
            waited += interval;
            if (Config.ready && root.win?.pageReady) {
                stop();
                startDelay.start();
            } else if (waited > 20000) {
                stop();
                root.fail("settings never became ready");
                root.report({ type: "done", failures: root.failures });
                Qt.quit();
            }
        }
    }

    Timer {
        id: startDelay
        interval: 1500
        onTriggered: root.start()
    }
}
