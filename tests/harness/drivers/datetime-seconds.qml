//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
//@ pragma Env QT_SCALE_FACTOR=1

// Harness driver (run.sh --driver): the real DateTime singleton (the bar
// clock's text) with config.json seeded by tests/test_datetime_seconds.py
// with time.format "hh:mm" and time.secondPrecision true. Reports one "clock"
// event per state: as seeded, after "Show seconds" is turned off through
// Config.options (live, like the settings app does), after it is turned back
// on; then "done".
import QtQuick
import Quickshell
import qs
import qs.modules.common
// @harness-imports

ShellRoot {
    id: root

    property int step: 0

    function report(payload) {
        console.info(`[harness:report] ${JSON.stringify(payload)}`);
    }

    function snapshot(label) {
        root.report({
            type: "clock",
            label: label,
            time: DateTime.time,
            format: Config.options.time.format,
            secondPrecision: Config.options.time.secondPrecision,
            secondsPrecision: DateTime.clock.precision === SystemClock.Seconds,
            minutesPrecision: DateTime.clock.precision === SystemClock.Minutes,
            screenLocked: GlobalStates.screenLocked,
        });
    }

    // Bindings settle on the next event loop turn after a Config change.
    function later(action) {
        laterComponent.createObject(root, { interval: 50, action: timer => {
            timer.destroy();
            action();
        } }).start();
    }

    function advance() {
        root.step += 1;
        switch (root.step) {
        case 1:
            root.snapshot("seeded");
            Config.options.time.secondPrecision = false;
            root.later(root.advance);
            break;
        case 2:
            root.snapshot("off");
            Config.options.time.secondPrecision = true;
            root.later(root.advance);
            break;
        case 3:
            root.snapshot("on");
            // Leave time for Config's debounced write, then quit.
            laterComponent.createObject(root, { interval: 600, action: timer => {
                timer.destroy();
                root.report({ type: "done" });
                Qt.quit();
            } }).start();
            break;
        }
    }

    Component {
        id: laterComponent
        Timer {
            id: laterTimer
            property var action: null
            onTriggered: laterTimer.action(laterTimer)
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
