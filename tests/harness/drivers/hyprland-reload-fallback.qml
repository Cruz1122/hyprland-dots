//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1

// Harness driver (run.sh --driver): Hyprland only watches
// custom/shell-settings.lua once its config has loaded the file, so an
// override written while it is not watched never applied. A write that no
// `configreloaded` follows must end with one `hyprctl reload config-only`;
// a write that Hyprland's autoreload answers must not reload again.
//
// Runs against a stub `hyprctl` on PATH that appends its arguments to
// $HYPRCTL_LOG (tests/test_hyprland_reload_fallback.py). Reports one
// "reload" event per scenario with the number of reloads it caused.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.settings.backends
import qs.modules.settings.core

ShellRoot {
    id: root

    readonly property var entry: SettingsRegistry.entry("hyprland.general.gaps_in")
    property int reloadsBefore: 0
    property bool answerWithAutoreload: false

    function report(payload) {
        console.info(`[harness:report] ${JSON.stringify(payload)}`);
    }

    function reloads() {
        const view = readerComponent.createObject(root, { path: Quickshell.env("HYPRCTL_LOG") });
        const text = view.text();
        view.destroy();
        return text.split("\n").filter(line => line.trim() === "reload config-only").length;
    }

    // Polls `check` every 100 ms up to `timeoutMs`, then calls done(ok).
    function waitFor(check, timeoutMs, done) {
        pollComponent.createObject(root, { deadline: Date.now() + timeoutMs, check: check, done: done }).start();
    }

    function unwatched() {
        root.reloadsBefore = root.reloads();
        backend.write(root.entry, 7);
        // Debounce (400 ms) + configurator + grace, with room to spare.
        root.waitFor(() => root.reloads() > root.reloadsBefore, 6000, () => {
            root.report({ type: "reload", scenario: "unwatched", expected: 1, actual: root.reloads() - root.reloadsBefore });
            root.autoreload();
        });
    }

    function autoreload() {
        root.reloadsBefore = root.reloads();
        root.answerWithAutoreload = true;
        backend.write(root.entry, 9);
        // Twice the grace period after the write: a fallback would have run.
        root.waitFor(() => false, 400 + 2 * backend.reloadGraceMs + 1500, () => {
            root.report({ type: "reload", scenario: "autoreload", expected: 0, actual: root.reloads() - root.reloadsBefore });
            root.report({ type: "done" });
            Qt.quit();
        });
    }

    HyprlandBackend {
        id: backend
        reloadGraceMs: 800

        // Stands in for Hyprland's autoreload event shortly after the write.
        onSucceeded: key => {
            if (root.answerWithAutoreload && key === root.entry.key)
                Qt.callLater(() => backend.hyprlandEvents.onRawEvent({ name: "configreloaded" }));
        }
    }

    Component {
        id: readerComponent
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

    Timer {
        interval: 100
        repeat: true
        running: true
        property int waited: 0
        onTriggered: {
            waited += interval;
            if (backend.available && root.entry) {
                stop();
                root.unwatched();
            } else if (waited > 20000) {
                stop();
                root.report({ type: "fatal", message: `backend never became available: ${backend.unavailableReason}` });
                Qt.quit();
            }
        }
    }
}
