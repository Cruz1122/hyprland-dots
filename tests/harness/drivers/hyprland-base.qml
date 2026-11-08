//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1

// Harness driver (run.sh --hyprland-stub --driver): HyprlandBackend defaults
// come from the dotfiles' base (scripts/settings/hyprbase.py on the seeded
// hyprland.lua), and while Game Mode is on the options it overrides show the
// user's stored value, say "Paused by Game Mode" and are only written to
// shell-settings.lua, never evaluated live.
//
// tests/test_hyprland_base.py serves `-j descriptions` from a fixture whose
// values stand for Game Mode's live state (animations off, gaps 0), so a
// stored value can be told apart from the live one. Reports one "check"
// event per assertion.
//
// Rows only learn about a change through succeeded(key), so the driver also
// checks that it fires when only the default (base loaded) or only the status
// note (Game Mode on/off with the app open) changes while read() stays put.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.settings.backends
import qs.modules.settings.core

ShellRoot {
    id: root

    readonly property string hyprDir: `${Quickshell.env("XDG_CONFIG_HOME")}/hypr`
    readonly property string overridesFile: `${root.hyprDir}/hyprland/shellOverrides/main.lua`
    readonly property string settingsFile: `${root.hyprDir}/custom/shell-settings.lua`
    readonly property string configurator: Quickshell.shellPath("scripts/hyprland/hyprconfigurator.py")
    // What GameModeToggle.qml sets through HyprlandConfig (--set on main.lua).
    readonly property var gameModeArgs: ["--set", "animations:enabled", "0", "--set", "decoration:blur:enabled", "0",
        "--set", "general:gaps_in", "0", "--set", "general:gaps_out", "0", "--set", "decoration:rounding", "0"]
    // Created after Game Mode's file is seeded, as when the app opens mid-game.
    property var backend: null
    property var store: null
    // Keys announced with succeeded(): all of them, and those announced in the
    // same turn the base became loaded.
    property var announced: []
    property var announcedAtBase: []
    property bool baseTick: false

    function report(payload) {
        console.info(`[harness:report] ${JSON.stringify(payload)}`);
    }

    function check(name, actual, expected) {
        root.report({ type: "check", name: name, expected: expected === undefined ? "undefined" : expected,
            actual: actual === undefined ? "undefined" : actual });
    }

    function entry(key) {
        return SettingsRegistry.entry(key);
    }

    function text(path) {
        const view = readerComponent.createObject(root, { path: path });
        const content = view.text();
        view.destroy();
        return content;
    }

    function evalCalls() {
        return root.text(Quickshell.env("HYPRCTL_LOG")).split("\n").filter(line => /^eval\b/.test(line.trim())).length;
    }

    function fatal(message) {
        root.report({ type: "fatal", message: message });
        Qt.quit();
    }

    // Runs argv, then done(exitCode).
    function run(argv, done) {
        const proc = procComponent.createObject(root, { command: argv });
        proc.exited.connect((code, status) => {
            proc.destroy();
            done(code);
        });
        proc.running = true;
    }

    // Polls `test` every 100 ms up to `timeoutMs`, then calls done(ok).
    function waitFor(test, timeoutMs, done) {
        pollComponent.createObject(root, { deadline: Date.now() + timeoutMs, test: test, done: done }).start();
    }

    function watch(b) {
        b.baseLoadedChanged.connect(() => {
            if (!b.baseLoaded)
                return;
            root.baseTick = true;
            Qt.callLater(() => root.baseTick = false);
        });
        b.succeeded.connect(key => {
            root.announced.push(key);
            if (root.baseTick)
                root.announcedAtBase.push(key);
        });
    }

    function reloaded() {
        root.backend.hyprlandEvents.onRawEvent({ name: "configreloaded" });
    }

    Component.onCompleted: root.run(["mkdir", "-p", root.overridesFile.replace(/\/[^/]*$/, "")], () => {
        root.run(["python3", root.configurator, "--file", root.overridesFile].concat(root.gameModeArgs), code => {
            if (code !== 0)
                return root.fatal(`could not seed Game Mode (${code})`);
            root.backend = backendComponent.createObject(root);
            root.watch(root.backend);
            // Rows read before hyprbase.py ends; the base always arrives later.
            for (const key of ["hyprland.misc.animate_manual_resizes", "hyprland.general.gaps_in"])
                root.backend.read(root.entry(key));
            root.store = storeComponent.createObject(root, { registry: SettingsRegistry, backends: { hyprland: root.backend } });
            root.waitFor(() => root.backend && root.backend.available && root.backend.baseLoaded
                && Object.keys(root.backend.gameModeOverrides).length > 0, 20000, ok => {
                if (!ok)
                    return root.fatal(`backend never ready: ${root.backend?.unavailableReason}`);
                root.gameModeOn();
            });
        });
    })

    function gameModeOn() {
        const b = root.backend;
        const animations = root.entry("hyprland.animations.enabled");
        const gapsIn = root.entry("hyprland.general.gaps_in");
        check("gameMode capability", b.capabilities.includes("gameMode"), true);
        // AnimationBackend gets the dotfiles curves and animations from here.
        check("basePayload has the dotfiles curves", "menu_decel" in (b.basePayload?.curves ?? {}), true);
        check("basePayload has the dotfiles animations", "windowsIn" in (b.basePayload?.animations ?? {}), true);
        // Its read() does not depend on the base: only the default changed.
        check("succeeded when the base loads (option outside Game Mode)",
            root.announcedAtBase.includes("hyprland.misc.animate_manual_resizes"), true);
        check("succeeded gaps_in when the base loads", root.announcedAtBase.includes("hyprland.general.gaps_in"), true);
        check("read animations.enabled is the stored value", b.read(animations), true);
        check("read gaps_in is the base value", b.read(gapsIn), 4);
        check("statusNote of a Game Mode option", b.statusNote(animations), "Paused by Game Mode");
        check("statusNote of another option", b.statusNote(root.entry("hyprland.misc.animate_manual_resizes")), "");
        check("dependent row stays enabled", root.store.isEnabled("hyprland.misc.animate_manual_resizes"), true);
        check("defaultValue gaps_in is the base", b.defaultValue(gapsIn), 4);
        check("store defaultValue gaps_in", root.store.defaultValue("hyprland.general.gaps_in"), 4);
        check("defaultValue of an option the dotfiles do not set",
            b.defaultValue(root.entry("hyprland.decoration.inactive_opacity")), 0.85);
        check("normal write accepted", root.store.write("hyprland.general.gaps_in", 7), true);
        root.waitFor(() => /gaps_in=7\b/.test(root.text(root.settingsFile)) && b.overrides["general:gaps_in"] === 7, 8000, ok => {
            check("write persisted to shell-settings.lua", ok, true);
            // Until Hyprland's reload the row shows the optimistic value; after
            // it, read() must come from shell-settings.lua, not the live value.
            root.reloaded();
            root.waitFor(() => !(gapsIn.key in b._optimistic) && !b.descriptionsProc.running && !b.listProc.running,
                8000, settled => {
                check("optimistic value dropped after the reload", settled, true);
                check("read after the write is the stored override", b.read(gapsIn), 7);
                check("live gaps_in stays Game Mode's", b.values["general:gaps_in"], 0);
                root.pausedPreview();
            });
        });
    }

    // A risky-style preview of a paused option is held, not evaluated, and
    // persist() writes it.
    function pausedPreview() {
        const b = root.backend;
        const gapsOut = root.entry("hyprland.general.gaps_out");
        const snap = b.snapshot([gapsOut]);
        check("preview of a paused option accepted", b.preview(gapsOut, 3), true);
        check("read during the preview", b.read(gapsOut), 3);
        b.restore(snap);
        check("read after restore", b.read(gapsOut), 5);
        check("preview accepted again", b.preview(gapsOut, 8), true);
        b.persist([gapsOut]);
        root.waitFor(() => /gaps_out=8\b/.test(root.text(root.settingsFile)), 8000, ok => {
            check("persisted preview written to shell-settings.lua", ok, true);
            // Debounce, configurator and reload fallback are done by now.
            root.waitFor(() => !b.busy, 8000, () => {
                check("no hyprctl eval while Game Mode is on", root.evalCalls(), 0);
                root.storeLiveValue();
            });
        });
    }

    // Stores Game Mode's own live value (rounding 0), so turning Game Mode off
    // or on changes only the status note of that row, not read().
    function storeLiveValue() {
        const b = root.backend;
        check("write rounding 0 accepted", root.store.write("hyprland.decoration.rounding", 0), true);
        root.waitFor(() => /rounding=0\b/.test(root.text(root.settingsFile)) && b.overrides["decoration:rounding"] === 0
            && !b.busy, 8000, ok => {
            check("rounding 0 persisted to shell-settings.lua", ok, true);
            root.brokenBase();
        });
    }

    function brokenBase() {
        root.run(["python3", "-c", "import sys; open(sys.argv[1], 'w').write('hl.config({ broken\\n')", `${root.hyprDir}/hyprland.lua`], () => {
            root.reloaded();
            root.waitFor(() => !root.backend.baseLoaded, 8000, ok => {
                check("broken base is not loaded", ok, true);
                check("basePayload is null while the base is unknown", root.backend.basePayload, null);
                check("defaultValue is unknown", root.backend.defaultValue(root.entry("hyprland.general.gaps_in")), undefined);
                check("store defaultValue is unknown", root.store.defaultValue("hyprland.general.gaps_in"), undefined);
                root.gameModeOff();
            });
        });
    }

    function gameModeOff() {
        const keys = [];
        for (let i = 1; i < root.gameModeArgs.length; i += 3)
            keys.push("--reset", root.gameModeArgs[i]);
        root.announced = [];
        root.run(["python3", root.configurator, "--file", root.overridesFile].concat(keys), () => {
            root.reloaded();
            const animations = root.entry("hyprland.animations.enabled");
            const rounding = root.entry("hyprland.decoration.rounding");
            root.waitFor(() => !root.backend.gameMode, 8000, ok => {
                check("Game Mode off", ok, true);
                check("statusNote after Game Mode", root.backend.statusNote(animations), "");
                check("read follows Hyprland again", root.backend.read(animations), false);
                check("read rounding unchanged when Game Mode ends", root.backend.read(rounding), 0);
                check("succeeded rounding when Game Mode ends", root.announced.includes(rounding.key), true);
                root.gameModeAgain();
            });
        });
    }

    // Game Mode starts while the app is open.
    function gameModeAgain() {
        root.announced = [];
        root.run(["python3", root.configurator, "--file", root.overridesFile].concat(root.gameModeArgs), code => {
            if (code !== 0)
                return root.fatal(`could not seed Game Mode again (${code})`);
            root.reloaded();
            const animations = root.entry("hyprland.animations.enabled");
            const rounding = root.entry("hyprland.decoration.rounding");
            root.waitFor(() => root.backend.gameMode && "decoration:rounding" in root.backend.gameModeOverrides, 8000, ok => {
                check("Game Mode on with the app open", ok, true);
                check("statusNote of rounding", root.backend.statusNote(rounding), "Paused by Game Mode");
                check("read rounding unchanged when Game Mode starts", root.backend.read(rounding), 0);
                check("succeeded rounding when Game Mode starts", root.announced.includes(rounding.key), true);
                check("succeeded animations.enabled when Game Mode starts", root.announced.includes(animations.key), true);
                root.previewBeforeGameMode();
            });
        });
    }

    // A preview of an option that Game Mode starts to override during the
    // confirmation must not cover Game Mode's live value: no eval on the
    // reloads that follow, none on restore.
    function previewBeforeGameMode() {
        const b = root.backend;
        const gapsOut = root.entry("hyprland.general.gaps_out");
        const keys = [];
        for (let i = 1; i < root.gameModeArgs.length; i += 3)
            keys.push("--reset", root.gameModeArgs[i]);
        root.run(["python3", root.configurator, "--file", root.overridesFile].concat(keys), () => {
            root.reloaded();
            root.waitFor(() => !b.gameMode && !b.busy, 8000, off => {
                check("Game Mode off before the preview", off, true);
                const snap = b.snapshot([gapsOut]);
                const before = root.evalCalls();
                check("preview of an option outside Game Mode accepted", b.preview(gapsOut, 9), true);
                root.waitFor(() => root.evalCalls() === before + 1 && !b.busy, 8000, evaluated => {
                    check("the preview is evaluated live", evaluated, true);
                    // Outside Game Mode a reload re-applies the preview once,
                    // after Game Mode's file has been read again.
                    root.reloaded();
                    root.waitFor(() => root.evalCalls() === before + 2 && !b.busy, 8000, () => root.waitFor(() => false, 300, () => {
                    check("a reload with Game Mode off re-applies the preview once", root.evalCalls() - before, 2);
                    root.run(["python3", root.configurator, "--file", root.overridesFile].concat(root.gameModeArgs), code => {
                        if (code !== 0)
                            return root.fatal(`could not seed Game Mode for the preview (${code})`);
                        // Taken before Game Mode's own reload: that reload
                        // must not re-apply the preview either, although the
                        // overrides are read only after it.
                        const mark = root.evalCalls();
                        root.reloaded();
                        root.waitFor(() => b.gameMode && "general:gaps_out" in b.gameModeOverrides && !b.busy, 8000, on => {
                            check("Game Mode overrides the previewed option", on && b.statusNote(gapsOut) === "Paused by Game Mode", true);
                            check("no eval of the preview on Game Mode's own reload", root.evalCalls() - mark, 0);
                            root.reloaded();
                            root.waitFor(() => false, 300, () => root.waitFor(() => !b.busy, 8000, () => {
                                check("no eval of the preview on a reload while Game Mode overrides it", root.evalCalls() - mark, 0);
                                b.restore(snap);
                                root.waitFor(() => false, 300, () => root.waitFor(() => !b.busy, 8000, () => {
                                    check("no eval on restore while Game Mode overrides it", root.evalCalls() - mark, 0);
                                    check("read after restore is the stored override", b.read(gapsOut), 8);
                                    root.report({ type: "done" });
                                    quitTimer.start();
                                }));
                            }));
                        });
                    });
                    }));
                });
            });
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
        id: procComponent
        Process {}
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

    Timer {
        id: quitTimer
        interval: 200
        onTriggered: Qt.quit()
    }
}
