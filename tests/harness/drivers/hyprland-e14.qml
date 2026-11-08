//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1

// Harness driver (run.sh --hyprland-stub --allow-config-writes --driver):
// the options added in wave 2 (E14) round-trip through HyprlandBackend.
// For each one the driver writes a value that differs from its default
// through SettingsStoreImpl, waits until the backend is idle, delivers
// Hyprland's `configreloaded` (the stub has no event socket) and checks that
// the row reads the value and counts as modified; then it reports the
// generated custom/shell-settings.lua, resets every option and checks that
// the file no longer sets them. tests/test_hyprland_e14.py checks the lines
// and runs `Hyprland --verify-config` on the reported file.
//
// It also checks the default of misc:initial_workspace_tracking: the
// dotfiles set it to `false`, an int option, which must read as 0 ("Off").
import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.settings.backends
import qs.modules.settings.core

ShellRoot {
    id: root

    readonly property string settingsFile: `${Quickshell.env("XDG_CONFIG_HOME")}/hypr/custom/shell-settings.lua`
    // key -> value written (each differs from the dotfiles' or Hyprland's default).
    readonly property var cases: [
        ["hyprland.input.scroll_factor", 1.5],
        ["hyprland.cursor.hide_on_key_press", true],
        ["hyprland.input.focus_on_close", 2],
        // drag_lock is enabled only while tap_and_drag is on: write it first.
        ["hyprland.input.touchpad.drag_lock", 2],
        ["hyprland.input.touchpad.tap_and_drag", false],
        ["hyprland.binds.workspace_back_and_forth", 1],
        ["hyprland.misc.middle_click_paste", false],
        ["hyprland.misc.initial_workspace_tracking", 2],
        ["hyprland.ecosystem.no_update_news", true],
        ["hyprland.ecosystem.no_donation_nag", true]
    ]
    property var backend: null
    property var store: null
    property int failures: 0

    function report(payload) {
        console.info(`[harness:report] ${JSON.stringify(payload)}`);
    }

    function check(name, ok, detail) {
        root.report(Object.assign({ type: "check", name: name, ok: !!ok }, detail ?? {}));
        if (!ok)
            root.failures++;
        return !!ok;
    }

    function finish() {
        root.report({ type: "done", failures: root.failures });
        Qt.quit();
    }

    function fatal(message) {
        root.report({ type: "fatal", message: message });
        root.finish();
    }

    function text(path) {
        const view = readerComponent.createObject(root, { path: path });
        const content = view.text();
        view.destroy();
        return content;
    }

    function waitFor(test, timeoutMs, done) {
        pollComponent.createObject(root, { deadline: Date.now() + timeoutMs, test: test, done: done }).start();
    }

    function entry(key) {
        return SettingsRegistry.entry(key);
    }

    function reloaded() {
        root.backend.hyprlandEvents.onRawEvent({ name: "configreloaded" });
    }

    // Idle (writes done), then `before()` while the optimistic values still
    // stand; a reload re-reads the overrides and `done(ok)` runs once every
    // option's modified state is `modified` (ok false after 10 s).
    function settle(before, modified, done) {
        root.waitFor(() => !root.backend.busy, 10000, idle => {
            before(idle);
            root.reloaded();
            root.waitFor(() => !root.backend.busy
                && root.cases.every(([key]) => root.backend.isModified(root.entry(key)) === modified), 10000, done);
        });
    }

    Component.onCompleted: {
        root.backend = backendComponent.createObject(root);
        root.store = storeComponent.createObject(root, { registry: SettingsRegistry, backends: { hyprland: root.backend } });
        root.waitFor(() => root.backend.available && root.backend.baseLoaded, 20000, ok => {
            if (!ok)
                return root.fatal(`backend never ready: ${root.backend.unavailableReason}`);
            root.defaults();
        });
    }

    function defaults() {
        for (const [key, value] of root.cases) {
            const e = root.entry(key);
            root.check(`${key}: registered`, !!e && e.backend === "hyprland", { key: key });
            const def = root.backend.defaultValue(e);
            root.check(`${key}: the written value differs from the default`, def !== undefined && JSON.stringify(def) !== JSON.stringify(value),
                { key: key, defaultValue: def ?? null, value: value });
        }
        const tracking = root.entry("hyprland.misc.initial_workspace_tracking");
        root.check("initial_workspace_tracking: the dotfiles' false reads as 0", root.backend.defaultValue(tracking) === 0,
            { defaultValue: root.backend.defaultValue(tracking) ?? null });
        root.writeAll();
    }

    function writeAll() {
        for (const [key, value] of root.cases)
            root.check(`${key}: write accepted`, root.store.write(key, value), { key: key, value: value });
        root.settle(idle => {
            root.check("backend idle after the writes", idle, {});
            for (const [key, value] of root.cases)
                root.check(`${key}: reads the written value`, JSON.stringify(root.store.value(key)) === JSON.stringify(value),
                    { key: key, read: root.store.value(key) ?? null, value: value });
        }, true, ok => {
            root.check("overrides listed after the reload", ok, {});
            for (const [key] of root.cases)
                root.check(`${key}: modified (set in shell-settings.lua)`, root.backend.isModified(root.entry(key)), { key: key });
            root.report({ type: "file", text: root.text(root.settingsFile) });
            root.resetAll();
        });
    }

    function resetAll() {
        for (const [key] of root.cases)
            root.check(`${key}: reset accepted`, root.store.reset(key), { key: key });
        root.settle(idle => root.check("backend idle after the resets", idle, {}), false, ok => {
            root.check("overrides listed after the reload", ok, {});
            const content = root.text(root.settingsFile);
            for (const [key] of root.cases) {
                const e = root.entry(key);
                const leaf = e.path.split(".").pop();
                root.check(`${key}: not modified after reset`, !root.backend.isModified(e), { key: key });
                root.check(`${key}: gone from shell-settings.lua`, content.indexOf(`${leaf}=`) < 0, { key: key });
            }
            root.report({ type: "fileAfterReset", text: content });
            root.finish();
        });
    }

    Component {
        id: backendComponent
        HyprlandBackend {}
    }

    Component {
        id: storeComponent
        SettingsStoreImpl {}
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
            property var test: null
            property var done: null
            interval: 100
            repeat: true
            onTriggered: {
                const ok = poll.test();
                if (ok || Date.now() > poll.deadline) {
                    poll.stop();
                    const done = poll.done;
                    poll.destroy();
                    done(ok);
                }
            }
        }
    }
}
