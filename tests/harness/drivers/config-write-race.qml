//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic

// Harness driver (run.sh --driver): Config must never drop a change because
// of its own file handling. Two scenarios, each reported as a "race" event
// with the expected, in-memory and on-disk values:
//
// reload: another process writes config.json, so Config schedules a reload;
//   40 ms later a local change starts Config's write timer, which fires after
//   the reload timer. The reload must not put the file's older value back.
// inFlight: a second change lands right after Config started writing the
//   first one (same 150 ms timeout, so it runs just after the write timer).
//   An async write re-applied what it wrote when it finished, undoing the
//   second change, and the next write then saw nothing to save.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common

ShellRoot {
    id: root

    property bool localValue: false
    property bool firstValue: false
    property bool secondValue: false

    function report(payload) {
        console.info(`[harness:report] ${JSON.stringify(payload)}`);
    }

    // A new FileView per read: its first load is synchronous, so the result
    // is the file as it is now (a reused FileView may return its previous read).
    function readDisk() {
        const view = readerComponent.createObject(root, { path: Directories.shellConfigPath });
        const text = view.text();
        view.destroy();
        try {
            return JSON.parse(text);
        } catch (e) {
            return null;
        }
    }

    Component {
        id: readerComponent
        FileView {
            blockLoading: true
            printErrors: false
        }
    }

    // Stands in for the main shell writing the same file.
    FileView {
        id: otherProcess
        path: Directories.shellConfigPath
        blockWrites: true
        printErrors: false
    }

    Component.onCompleted: Config.readWriteDelay = 150

    Timer {
        id: waitReady
        interval: 50
        repeat: true
        running: true
        property int waited: 0
        onTriggered: {
            waited += interval;
            if (Config.ready) {
                stop();
                // Let the first load settle before writing from outside.
                externalWrite.start();
            } else if (waited > 20000) {
                stop();
                root.report({ type: "fatal", message: "config never became ready" });
                Qt.quit();
            }
        }
    }

    // ------------------------------------------------------------ reload

    Timer {
        id: externalWrite
        interval: 500
        onTriggered: {
            const data = root.readDisk();
            data.appearance.extraBackgroundTint = !data.appearance.extraBackgroundTint;
            otherProcess.setText(JSON.stringify(data, null, 2));
            localChange.start();
        }
    }

    Timer {
        id: localChange
        interval: 40
        onTriggered: {
            root.localValue = !Config.options.appearance.transparency.enable;
            Config.options.appearance.transparency.enable = root.localValue;
            reloadSettle.start();
        }
    }

    Timer {
        id: reloadSettle
        interval: 1500
        onTriggered: {
            const disk = root.readDisk();
            root.report({
                type: "race",
                scenario: "reload",
                expected: root.localValue,
                memory: Config.options.appearance.transparency.enable,
                disk: disk?.appearance?.transparency?.enable
            });
            firstChange.start();
        }
    }

    // ---------------------------------------------------------- inFlight

    Timer {
        id: firstChange
        interval: 200
        onTriggered: {
            root.firstValue = !Config.options.bar.verbose;
            root.secondValue = !Config.options.bar.borderless;
            // Config's write timer starts first, so it fires first.
            Config.options.bar.verbose = root.firstValue;
            secondChange.start();
        }
    }

    Timer {
        id: secondChange
        interval: Config.readWriteDelay
        onTriggered: {
            Config.options.bar.borderless = root.secondValue;
            inFlightSettle.start();
        }
    }

    Timer {
        id: inFlightSettle
        interval: 1500
        onTriggered: {
            const disk = root.readDisk();
            root.report({
                type: "race",
                scenario: "inFlight",
                expected: [root.firstValue, root.secondValue],
                memory: [Config.options.bar.verbose, Config.options.bar.borderless],
                disk: [disk?.bar?.verbose, disk?.bar?.borderless]
            });
            root.report({ type: "done" });
            Qt.quit();
        }
    }
}
