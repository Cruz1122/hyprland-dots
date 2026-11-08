//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1

// Harness driver (run.sh --hyprland-stub --driver): AnimationBackend writes,
// failures and reloads, observed from the outside. tests/test_animation_backend.py
// puts the hyprctl stub and the python3 shim (tests/harness/stubs) first on
// PATH, so every hyprctl call lands in $HYPRCTL_LOG and every python3 call in
// $PYTHON3_SHIM_LOG; the base comes from tests/fixtures/hyprbase-sample.json
// ($ANIM_BASE_FIXTURE). Reports one "scenario" event per case with what it
// expected and what happened.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.settings.backends

ShellRoot {
    id: root

    readonly property string hyprctlLog: Quickshell.env("HYPRCTL_LOG") ?? ""
    readonly property string shimLog: Quickshell.env("PYTHON3_SHIM_LOG") ?? ""
    readonly property string shimFail: Quickshell.env("PYTHON3_SHIM_FAIL") ?? ""
    property bool answerWithAutoreload: false
    property var failures: []
    property var mark: null
    property int step: 0
    property var second: null
    property var raced: null

    function entry(card) {
        return { key: `animation.${card}`, path: card, backend: "animation" };
    }

    function value(speed, curve, style, enabled) {
        return { enabled: enabled ?? true, speed: speed, curve: curve, style: style };
    }

    function report(payload) {
        console.info(`[harness:report] ${JSON.stringify(payload)}`);
    }

    function readText(path) {
        const view = readerComponent.createObject(root, { path: path });
        const text = view.text();
        view.destroy();
        return text ?? "";
    }

    function writeText(path, text) {
        const view = writerComponent.createObject(root, { path: path });
        view.setText(text);
        view.destroy();
    }

    function lines(path) {
        return root.readText(path).split("\n").filter(line => line.length > 0);
    }

    // Counters since the last mark().
    function counts() {
        const hypr = root.lines(root.hyprctlLog);
        const shim = root.lines(root.shimLog);
        return {
            reloads: hypr.filter(l => l.trim() === "reload config-only").length,
            evals: hypr.filter(l => l.startsWith("eval ")).length,
            generatorCalls: shim.filter(l => l.includes("animationsgen.py") && l.includes("--apply-json")).length
        };
    }

    function begin() {
        root.mark = root.counts();
        root.failures = [];
    }

    function since() {
        const now = root.counts();
        return {
            reloads: now.reloads - root.mark.reloads,
            evals: now.evals - root.mark.evals,
            generatorCalls: now.generatorCalls - root.mark.generatorCalls
        };
    }

    function fileText() {
        return root.readText(backend.animationsFile);
    }

    function animationLines() {
        return root.fileText().split("\n").filter(l => l.startsWith("hl.animation("));
    }

    // Polls `check` every 100 ms up to `timeoutMs`, then calls done(ok).
    function waitFor(check, timeoutMs, done) {
        pollComponent.createObject(root, { deadline: Date.now() + timeoutMs, check: check, done: done }).start();
    }

    // Waits until the backend is idle, then past the reload grace period (a
    // fallback reload would have run) and the -j animations confirmation.
    function settle(target, done) {
        root.waitFor(() => false, 450, () => root.waitFor(() => !target.busy, 10000, idle => {
            root.waitFor(() => false, target.reloadGraceMs + 900, () => done(idle));
        }));
    }

    function scenario(name, expected, actual) {
        root.report({ type: "scenario", name: name, expected: expected, actual: actual });
        root.next();
    }

    readonly property var steps: [
        // Hyprland does not watch the new file yet: no configreloaded, one reload.
        () => {
            root.begin();
            backend.write(root.entry("windowsIn"), root.value(2, "emphasizedDecel", "popin 85%"));
            root.settle(backend, idle => root.scenario("unwatched", {
                idle: true, reloads: 1, evals: 1, generatorCalls: 1, failures: 0, capability: true,
                lines: ['hl.animation({ leaf = "windowsIn", enabled = true, speed = 2, bezier = "emphasizedDecel", style = "popin 85%" })',
                    'hl.animation({ leaf = "fadeIn", enabled = true, speed = 2, bezier = "emphasizedDecel" })']
            }, Object.assign(root.since(), {
                idle: idle, failures: root.failures.length, capability: backend.capabilities.includes("animationsLoaded"),
                lines: root.animationLines()
            })));
        },
        // Hyprland's autoreload answers the write: no extra reload.
        () => {
            root.begin();
            root.answerWithAutoreload = true;
            backend.write(root.entry("border"), root.value(6, "emphasizedDecel", ""));
            root.settle(backend, idle => {
                root.answerWithAutoreload = false;
                root.scenario("autoreload", { idle: true, reloads: 0, evals: 1, generatorCalls: 1, failures: 0 },
                    Object.assign(root.since(), { idle: idle, failures: root.failures.length }));
            });
        },
        // Writing the value already shown starts nothing.
        () => {
            root.begin();
            const ok = backend.write(root.entry("border"), root.value(6, "emphasizedDecel", ""));
            root.settle(backend, idle => root.scenario("unchanged", { ok: true, reloads: 0, evals: 0, generatorCalls: 0 },
                Object.assign(root.since(), { ok: ok })));
        },
        // Rejected before anything runs: nothing to compensate.
        () => {
            root.begin();
            const before = root.fileText();
            const ok = backend.write(root.entry("windowsIn"), root.value(2, "emphasizedDecel", "slidefade 20%"));
            root.settle(backend, idle => root.scenario("invalid", {
                ok: false, reloads: 0, evals: 0, generatorCalls: 0, failures: 1, unchangedFile: true
            }, Object.assign(root.since(), { ok: ok, failures: root.failures.length, unchangedFile: root.fileText() === before })));
        },
        // Hyprland rejects the value (stub eval failure, exit 7): the generator
        // reloads, writes nothing and the row goes back to the stored value.
        () => {
            root.begin();
            const before = root.fileText();
            backend.write(root.entry("zoomFactor"), root.value(7.77, "standardDecel", ""));
            const optimistic = backend.read(root.entry("zoomFactor")).speed;
            root.settle(backend, idle => root.scenario("rejected", {
                optimistic: 7.77, reloads: 1, evals: 1, generatorCalls: 1, failures: 1, unchangedFile: true, shown: 3,
                message: true
            }, Object.assign(root.since(), {
                optimistic: optimistic, failures: root.failures.length, unchangedFile: root.fileText() === before,
                shown: backend.read(root.entry("zoomFactor")).speed,
                message: root.failures.length === 1 && root.failures[0].includes("stub failure")
            })));
        },
        // The generator fails for another reason (shim: exit 5): the backend reloads.
        () => {
            root.begin();
            root.writeText(root.shimFail, "5");
            backend.write(root.entry("border"), root.value(8, "emphasizedDecel", ""));
            root.settle(backend, idle => root.scenario("generatorFailure", {
                reloads: 1, evals: 0, generatorCalls: 1, failures: 1, shown: 6
            }, Object.assign(root.since(), { failures: root.failures.length, shown: backend.read(root.entry("border")).speed })));
        },
        // A preset is one transaction for the 10 cards.
        () => {
            root.begin();
            backend.write(root.entry("preset"), "smooth");
            root.settle(backend, idle => root.scenario("preset", {
                reloads: 1, evals: 1, generatorCalls: 1, failures: 0, preset: "smooth", primaryLines: 10, modified: true
            }, Object.assign(root.since(), {
                failures: root.failures.length, preset: backend.read(root.entry("preset")),
                primaryLines: root.animationLines().filter(l => !/leaf = "fade/.test(l)).length,
                modified: backend.isModified(root.entry("windowsMove"))
            })));
        },
        // Disabling keeps the tuple in the file; enabling again restores it.
        () => {
            root.begin();
            const original = root.fileText();
            const shown = backend.read(root.entry("windowsMove"));
            backend.write(root.entry("windowsMove"), Object.assign({}, shown, { enabled: false }));
            root.settle(backend, () => {
                const disabled = root.animationLines().find(l => l.includes('leaf = "windowsMove"')) ?? "";
                backend.write(root.entry("windowsMove"), Object.assign({}, backend.read(root.entry("windowsMove")), { enabled: true }));
                root.settle(backend, () => root.scenario("disableEnable", {
                    disabledLine: 'hl.animation({ leaf = "windowsMove", enabled = false, speed = 4.5, bezier = "emphasizedDecel", style = "slide" })',
                    restored: true, generatorCalls: 2, evals: 2, reloads: 2, failures: 0
                }, Object.assign(root.since(), { disabledLine: disabled, restored: root.fileText() === original, failures: root.failures.length })));
            });
        },
        // "default" removes every animation line and keeps the curves.
        () => {
            root.begin();
            backend.write(root.entry("curves"), [{ name: "ii_mine", type: "bezier", points: [0.2, 0, 0, 1], label: "Mine" }]);
            root.settle(backend, () => {
                const mark = root.since();
                backend.write(root.entry("preset"), "default");
                root.settle(backend, () => {
                    const total = root.since();
                    root.scenario("defaultPreset", {
                        presetGeneratorCalls: 1, presetEvals: 0, animationLines: 0, keepsCurve: true, preset: "default", modified: false
                    }, {
                        presetGeneratorCalls: total.generatorCalls - mark.generatorCalls, presetEvals: total.evals - mark.evals,
                        animationLines: root.animationLines().length, keepsCurve: root.fileText().includes('hl.curve("ii_mine"'),
                        preset: backend.read(root.entry("preset")), modified: backend.isModified(root.entry("windowsIn"))
                    });
                });
            });
        },
        // While Game Mode is on, rows show the stored value with a note.
        () => {
            const stored = backend.read(root.entry("windowsIn"));
            // run.sh does not create hyprland/shellOverrides/ in the sandbox.
            const file = backend.shellOverridesFile;
            mkdir.command = ["mkdir", "-p", file.slice(0, file.lastIndexOf("/"))];
            mkdir.running = true;
            // Game Mode writes its file and reloads Hyprland, whose event
            // makes the backend read the file again (a watch misses creation).
            root.waitFor(() => !mkdir.running, 5000, () => {
                root.writeText(file, "-- DO NOT EDIT THIS FILE.\nhl.config({ animations = { enabled = 0 } })\n");
                backend.hyprlandEvents.onRawEvent({ name: "configreloaded" });
            });
            root.waitFor(() => backend.gameMode, 6000, on => {
                const note = backend.statusNote(root.entry("windowsIn"));
                const presetNote = backend.statusNote(root.entry("preset"));
                const value = backend.read(root.entry("windowsIn"));
                root.writeText(backend.shellOverridesFile, "-- DO NOT EDIT THIS FILE.\n");
                backend.hyprlandEvents.onRawEvent({ name: "configreloaded" });
                root.waitFor(() => !backend.gameMode, 5000, off => root.scenario("gameMode", {
                    on: true, note: "Paused by Game Mode", presetNote: "Paused by Game Mode", storedValue: true, off: true, noteAfter: ""
                }, {
                    on: on, note: note, presetNote: presetNote, storedValue: JSON.stringify(value) === JSON.stringify(stored), off: off,
                    noteAfter: backend.statusNote(root.entry("windowsIn"))
                }));
            });
        },
        // Two changes to one card inside the reload grace period: the
        // confirmation compares Hyprland with the last write, which is what
        // it reports (the stub shows windowsIn at speed 2), not the first one.
        () => {
            root.raced = backendComponent.createObject(root, { reloadGraceMs: 2000 });
            root.waitFor(() => root.raced.available && root.raced.base !== null, 10000, () => {
                root.begin();
                root.raced.write(root.entry("windowsIn"), root.value(1.5, "emphasizedDecel", "popin 85%"));
                // The first write has run and its fallback reload is pending.
                root.waitFor(() => root.raced.reloadFallback.running && root.raced._inflight === null, 6000, armed => {
                    root.raced.write(root.entry("windowsIn"), root.value(2, "emphasizedDecel", "popin 85%"));
                    root.settle(root.raced, idle => root.scenario("twoWritesInGrace", {
                        armed: true, idle: true, generatorCalls: 2, evals: 2, reloads: 1, failures: 0, capability: true, shown: 2
                    }, Object.assign(root.since(), {
                        armed: armed, idle: idle, failures: root.failures.length,
                        capability: root.raced.capabilities.includes("animationsLoaded"),
                        shown: root.raced.read(root.entry("windowsIn")).speed
                    })));
                });
            });
        },
        // A backend whose first write Hyprland does not report drops the
        // capability and says so (the stub keeps serving the old windowsOut).
        () => {
            root.second = backendComponent.createObject(root);
            root.waitFor(() => root.second.available && root.second.base !== null, 10000, () => {
                root.begin();
                const had = root.second.capabilities.includes("animationsLoaded");
                root.second.write(root.entry("windowsOut"), root.value(5, "emphasizedDecel", "popin 90%"));
                root.settle(root.second, () => root.scenario("notLoaded", {
                    had: true, capability: false, failures: 1, message: "Hyprland did not load the animation settings: update hyprland.lua"
                }, {
                    had: had, capability: root.second.capabilities.includes("animationsLoaded"), failures: root.failures.length,
                    message: root.failures[0] ?? ""
                }));
            });
        }
    ]

    function next() {
        if (root.step >= root.steps.length) {
            root.report({ type: "done" });
            Qt.quit();
            return;
        }
        root.steps[root.step++]();
    }

    AnimationBackend {
        id: backend
        reloadGraceMs: 800
        baseFixture: Quickshell.env("ANIM_BASE_FIXTURE") ?? ""
        onFailed: (key, message) => root.failures = root.failures.concat([message])
        // Stands in for Hyprland's autoreload event shortly after the write.
        onSucceeded: key => {
            if (root.answerWithAutoreload)
                Qt.callLater(() => backend.hyprlandEvents.onRawEvent({ name: "configreloaded" }));
        }
    }

    Component {
        id: backendComponent
        AnimationBackend {
            reloadGraceMs: 800
            baseFixture: Quickshell.env("ANIM_BASE_FIXTURE") ?? ""
            onFailed: (key, message) => root.failures = root.failures.concat([message])
        }
    }

    Process {
        id: mkdir
    }

    Component {
        id: readerComponent
        FileView {
            blockLoading: true
            printErrors: false
        }
    }

    Component {
        id: writerComponent
        FileView {
            blockWrites: true
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
            if (backend.available && backend.base !== null) {
                stop();
                root.next();
            } else if (waited > 20000) {
                stop();
                root.report({ type: "fatal", message: `backend never became available: ${backend.unavailableReason} (base: ${backend.base !== null})` });
                Qt.quit();
            }
        }
    }
}
