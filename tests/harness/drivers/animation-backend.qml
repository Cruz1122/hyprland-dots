//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1

// Harness driver (run.sh --hyprland-stub --driver): AnimationBackend writes,
// failures and reloads, observed from the outside. tests/test_animation_backend.py
// puts the hyprctl stub and the python3 shim (tests/harness/stubs) first on
// PATH, so every hyprctl call lands in $HYPRCTL_LOG and every python3 call in
// $PYTHON3_SHIM_LOG; the base comes from tests/fixtures/hyprbase-sample.json
// ($ANIM_BASE_FIXTURE). Reports one "scenario" event per case with what it
// expected and what happened. The shim can hold a generator call
// ($PYTHON3_SHIM_DELAY) and the test's hyprctl wrapper can fail one
// `-j animations` read ($HYPRCTL_ANIMATIONS_FAIL).
import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.settings.backends

ShellRoot {
    id: root

    readonly property string hyprctlLog: Quickshell.env("HYPRCTL_LOG") ?? ""
    readonly property string shimLog: Quickshell.env("PYTHON3_SHIM_LOG") ?? ""
    readonly property string shimFail: Quickshell.env("PYTHON3_SHIM_FAIL") ?? ""
    readonly property string shimDelay: Quickshell.env("PYTHON3_SHIM_DELAY") ?? ""
    readonly property string animationsFail: Quickshell.env("HYPRCTL_ANIMATIONS_FAIL") ?? ""
    readonly property string baseFixturePath: Quickshell.env("ANIM_BASE_FIXTURE") ?? ""
    // Keys the main backend announced with succeeded().
    property var announced: []
    property var late: null
    property var flaky: null
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

    function animationReads() {
        return root.lines(root.hyprctlLog).filter(l => l.trim() === "-j animations").length;
    }

    function listCalls() {
        return root.lines(root.shimLog).filter(l => l.includes("animationsgen.py") && l.includes("--list")).length;
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
        // While Game Mode is on, rows show the stored value with a note, and
        // a managed card hears succeeded() when Game Mode starts and ends
        // (only its status note changes; rows learn about it from that signal).
        () => {
            root.begin();
            // The tuple the stub reports for windowsIn: later confirmations
            // compare every managed card with it.
            backend.write(root.entry("windowsIn"), root.value(2, "emphasizedDecel", "popin 85%"));
            root.settle(backend, () => {
                const stored = backend.read(root.entry("windowsIn"));
                const managed = backend.isModified(root.entry("windowsIn"));
                // run.sh does not create hyprland/shellOverrides/ in the sandbox.
                const file = backend.shellOverridesFile;
                mkdir.command = ["mkdir", "-p", file.slice(0, file.lastIndexOf("/"))];
                mkdir.running = true;
                // Game Mode writes its file and reloads Hyprland, whose event
                // makes the backend read the file again (a watch misses creation).
                root.waitFor(() => !mkdir.running, 5000, () => {
                    root.announced = [];
                    root.writeText(file, "-- DO NOT EDIT THIS FILE.\nhl.config({ animations = { enabled = 0 } })\n");
                    backend.hyprlandEvents.onRawEvent({ name: "configreloaded" });
                    root.waitFor(() => backend.gameMode, 6000, on => {
                        const announcedOn = root.announced.includes("animation.windowsIn");
                        const note = backend.statusNote(root.entry("windowsIn"));
                        const presetNote = backend.statusNote(root.entry("preset"));
                        const value = backend.read(root.entry("windowsIn"));
                        root.announced = [];
                        root.writeText(backend.shellOverridesFile, "-- DO NOT EDIT THIS FILE.\n");
                        backend.hyprlandEvents.onRawEvent({ name: "configreloaded" });
                        root.waitFor(() => !backend.gameMode, 5000, off => root.scenario("gameMode", {
                            managed: true, on: true, note: "Paused by Game Mode", presetNote: "Paused by Game Mode", storedValue: true,
                            announcedOn: true, off: true, noteAfter: "", announcedOff: true
                        }, {
                            managed: managed, on: on, note: note, presetNote: presetNote,
                            storedValue: JSON.stringify(value) === JSON.stringify(stored), announcedOn: announcedOn, off: off,
                            noteAfter: backend.statusNote(root.entry("windowsIn")),
                            announcedOff: root.announced.includes("animation.windowsIn")
                        }));
                    });
                });
            });
        },
        // A configreloaded while the generator still runs starts a read of the
        // old file: the shown value must stay the written one until a read
        // that started after the write ends.
        () => {
            root.begin();
            const lists = root.listCalls();
            root.writeText(root.shimDelay, "2");
            backend.write(root.entry("border"), root.value(5, "emphasizedDecel", ""));
            root.waitFor(() => backend.runner.running && backend._inflight !== null, 5000, started => {
                backend.hyprlandEvents.onRawEvent({ name: "configreloaded" });
                root.waitFor(() => !backend.listProc.running && root.listCalls() > lists, 5000, listed => {
                    const during = backend.read(root.entry("border")).speed;
                    const stillApplying = backend.runner.running;
                    root.settle(backend, idle => root.scenario("reloadDuringApply", {
                        started: true, listed: true, stillApplying: true, during: 5, after: 5, idle: true,
                        reloads: 0, evals: 1, generatorCalls: 1, failures: 0
                    }, Object.assign(root.since(), {
                        started: started, listed: listed, stillApplying: stillApplying, during: during,
                        after: backend.read(root.entry("border")).speed, idle: idle, failures: root.failures.length
                    })));
                });
            });
        },
        // The base arrives after the rows read (as sharedBase does in the
        // app): managed and unmanaged cards both hear succeeded(), because
        // their default changed even where the shown value did not.
        () => {
            root.late = baselessComponent.createObject(root);
            root.waitFor(() => root.late.loaded, 10000, ready => {
                const managedCard = root.entry("windowsIn");
                const unmanagedCard = root.entry("layersIn");
                const shownBefore = JSON.stringify(root.late.read(managedCard));
                root.late.read(unmanagedCard);
                const heard = [];
                root.late.succeeded.connect(key => heard.push(key));
                const unknownBefore = root.late.defaultValue(managedCard) === undefined;
                root.late.sharedBase = JSON.parse(root.readText(root.baseFixturePath));
                root.scenario("baseArrives", {
                    ready: true, managed: true, unknownBefore: true, knownAfter: true, sameShown: true,
                    managedAnnounced: true, unmanagedAnnounced: true
                }, {
                    ready: ready, managed: root.late.isModified(managedCard), unknownBefore: unknownBefore,
                    knownAfter: root.late.defaultValue(managedCard) !== undefined,
                    sameShown: JSON.stringify(root.late.read(managedCard)) === shownBefore,
                    managedAnnounced: heard.includes(managedCard.key), unmanagedAnnounced: heard.includes(unmanagedCard.key)
                });
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
        // A failed `-j animations` read (the wrapper fails it once) is not a
        // mismatch: the capability stays and the check runs again after the
        // next reload, which then confirms the write (the fixture shows it).
        () => {
            root.flaky = backendComponent.createObject(root);
            root.waitFor(() => root.flaky.available && root.flaky.base !== null, 10000, () => {
                root.begin();
                const reads = root.animationReads();
                root.writeText(root.animationsFail, "1");
                root.flaky.write(root.entry("layersIn"), root.value(1.5, "emphasizedDecel", "popin 80%"));
                root.settle(root.flaky, () => {
                    const first = {
                        reads: root.animationReads() - reads, failures: root.failures.length,
                        capability: root.flaky.capabilities.includes("animationsLoaded"), confirmed: root.flaky._confirmed
                    };
                    root.flaky.hyprlandEvents.onRawEvent({ name: "configreloaded" });
                    root.settle(root.flaky, () => root.scenario("transientRead", {
                        firstReads: 1, firstFailures: 0, firstCapability: true, firstConfirmed: false,
                        reads: 2, failures: 0, capability: true, confirmed: true
                    }, {
                        firstReads: first.reads, firstFailures: first.failures, firstCapability: first.capability,
                        firstConfirmed: first.confirmed, reads: root.animationReads() - reads, failures: root.failures.length,
                        capability: root.flaky.capabilities.includes("animationsLoaded"), confirmed: root.flaky._confirmed
                    }));
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
        },
        // hyprland.lua without the require (here: commented out) has no
        // animationsLoaded capability; putting the line back restores it.
        () => {
            const original = root.readText(backend.hyprlandFile);
            const had = backend.capabilities.includes("animationsLoaded");
            const commented = original.replace('    pcall(require, "custom.shell-animations")',
                '    -- pcall(require, "custom.shell-animations")');
            root.writeText(backend.hyprlandFile, commented);
            backend.hyprlandEvents.onRawEvent({ name: "configreloaded" });
            root.waitFor(() => !backend.requiresFile, 5000, dropped => {
                const capability = backend.capabilities.includes("animationsLoaded");
                root.writeText(backend.hyprlandFile, original);
                backend.hyprlandEvents.onRawEvent({ name: "configreloaded" });
                root.waitFor(() => backend.requiresFile, 5000, back => root.scenario("noRequire", {
                    had: true, edited: true, dropped: true, capability: false, restored: true, capabilityAgain: true
                }, {
                    had: had, edited: commented !== original, dropped: dropped, capability: capability, restored: back,
                    capabilityAgain: backend.capabilities.includes("animationsLoaded")
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
            root.announced = root.announced.concat([key]);
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

    // No base yet, as in the app before HyprlandBackend's first hyprbase.py run.
    Component {
        id: baselessComponent
        AnimationBackend {
            reloadGraceMs: 800
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
