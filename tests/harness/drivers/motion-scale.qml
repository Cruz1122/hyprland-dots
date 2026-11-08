//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
//@ pragma Env QT_SCALE_FACTOR=1

// Harness driver (run.sh --driver): the real Appearance singleton follows
// appearance.animations from config.json (seeded with durationScale 0.5 by
// tests/test_motion_scale.py), then live changes made through Config.options:
// reduceMotion, then back to the normal speed. Reports one "motion" event per
// state, one "finish" event per animation started under reduceMotion, then
// "done".
import QtQuick
import Quickshell
import qs.modules.common
// @harness-imports

ShellRoot {
    id: root

    property var held: null
    property int step: 0

    function report(payload) {
        console.info(`[harness:report] ${JSON.stringify(payload)}`);
    }

    function snapshot(label) {
        const a = Appearance.animation;
        root.report({
            type: "motion",
            label: label,
            factor: Appearance.animationFactor,
            elementMove: a.elementMove.duration,
            elementMoveSmall: a.elementMoveSmall.duration,
            elementMoveEnter: a.elementMoveEnter.duration,
            elementMoveExit: a.elementMoveExit.duration,
            elementMoveFast: a.elementMoveFast.duration,
            elementResize: a.elementResize.duration,
            clickBounce: a.clickBounce.duration,
            scroll: a.scroll.duration,
            menuDecel: a.menuDecel.duration,
            elementMoveVelocity: a.elementMove.velocity,
            elementMoveFastVelocity: a.elementMoveFast.velocity,
            // An animation created from a preset factory keeps its binding.
            heldFactoryDuration: root.held ? root.held.duration : null,
            rawCurveDuration: Appearance.animationCurves.expressiveDefaultSpatialDuration,
            // Appearance.scaled() itself; the panels that call it are checked
            // statically in tests/test_motion_contract.py.
            scaledHelper520: Appearance.scaled(520),
        });
    }

    // Starts an animation and records whether `finished` arrived inside
    // start() (synchronously) or later from the animation timer.
    function probeFinish(label, animation) {
        let count = 0;
        animation.finished.connect(() => count++);
        animation.start();
        const duringStart = count;
        const runningAfterStart = animation.running;
        const startedAt = Date.now();
        laterComponent.createObject(root, { interval: 10, repeat: true, action: timer => {
            if (count === 0 && Date.now() - startedAt < 3000)
                return;
            timer.stop();
            timer.destroy();
            root.report({ type: "finish", label: label, duration: animation.duration, duringStart: duringStart,
                runningAfterStart: runningAfterStart, finishedLater: count - duringStart, elapsedMs: Date.now() - startedAt });
            animation.destroy();
            root.advance();
        } }).start();
    }

    function advance() {
        root.step += 1;
        const options = Config.options.appearance.animations;
        switch (root.step) {
        case 1:
            root.held = Appearance.animation.elementMove.numberAnimation.createObject(root, { target: probe, property: "a", from: 0, to: 1 });
            root.snapshot("seeded");
            options.reduceMotion = true;
            root.snapshot("reduced");
            root.probeFinish("elementMoveFast", Appearance.animation.elementMoveFast.numberAnimation.createObject(root, { target: probe, property: "b", from: 0, to: 1 }));
            break;
        case 2:
            root.probeFinish("elementMove", Appearance.animation.elementMove.numberAnimation.createObject(root, { target: probe, property: "c", from: 0, to: 1 }));
            break;
        case 3:
            // Control case for the 1 ms floor: what a true 0 ms animation does.
            root.probeFinish("zeroControl", zeroComponent.createObject(root, { target: probe, property: "d", from: 0, to: 1 }));
            break;
        case 4:
            options.reduceMotion = false;
            options.durationScale = 1;
            root.snapshot("normal");
            // Leave time for Config's debounced write, then quit.
            laterComponent.createObject(root, { interval: 600, action: timer => {
                timer.destroy();
                root.report({ type: "done" });
                Qt.quit();
            } }).start();
            break;
        }
    }

    Item {
        id: probe
        property real a: 0
        property real b: 0
        property real c: 0
        property real d: 0
    }

    Component {
        id: zeroComponent
        NumberAnimation {
            duration: 0 // motion-ok: control case of the harness driver
        }
    }

    Component {
        id: laterComponent
        Timer {
            id: later
            property var action: null
            onTriggered: later.action(later)
        }
    }

    Timer {
        interval: 50
        repeat: true
        running: true
        property int waited: 0
        onTriggered: {
            waited += interval;
            if (Config.ready) {
                stop();
                root.advance();
            } else if (waited > 20000) {
                stop();
                root.report({ type: "fatal", message: "Config never became ready" });
                Qt.quit();
            }
        }
    }
}
