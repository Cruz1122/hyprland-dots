//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
//@ pragma Env QT_SCALE_FACTOR=1

// Harness driver (run.sh --driver): closing the settings window must not
// drop work the backends still have to do. Opens the real settings.qml,
// previews a risky Hyprland value (keyboard layout, pending confirmation),
// makes a normal Hyprland write (held back while the confirmation lasts) and
// closes the window at once. The app has to revert the preview and write the
// held change before it quits by itself; quitting right away did neither.
// First, closing and presenting the window again (what the IPC show/open/
// reveal calls do) must cancel the quit.
//
// Runs against a stub `hyprctl` on PATH that appends its arguments to
// $HYPRCTL_LOG (tests/test_settings_close.py checks the log afterwards). The
// driver reports "done" before closing, since the app quits the process.
import QtQuick
import Quickshell
import qs.modules.common
// @harness-imports

ShellRoot {
    id: root

    property var win: null

    function report(payload) {
        console.info(`[harness:report] ${JSON.stringify(payload)}`);
    }

    function fail(message) {
        root.report({ type: "fatal", message: message });
        Qt.quit();
    }

    // With nothing pending the app would quit on the next poll (50 ms).
    function reopen() {
        root.win.close();
        if (root.win.visible)
            return root.fail("closing did not hide the window");
        root.win.present();
        laterComponent.createObject(root, { interval: 600, action: () => {
            root.report({ type: "reopened", visible: root.win.visible });
            root.run();
        } }).start();
    }

    function run() {
        if (!SettingsStore.write("hyprland.input.kb_layout", ["us"]))
            return root.fail("the keyboard preview was rejected");
        if (!SettingsStore.pendingConfirmation)
            return root.fail("the keyboard change did not wait for confirmation");
        if (!SettingsStore.write("hyprland.general.gaps_in", 7))
            return root.fail("the gaps write was rejected");
        root.report({ type: "done" });
        root.win.close();
        // Still running after close: the app must quit by itself later.
        root.report({ type: "closed", visible: root.win.visible });
    }

    Timer {
        interval: 100
        repeat: true
        running: root.win !== null
        property int waited: 0
        onTriggered: {
            waited += interval;
            if (SettingsStore.isAvailable("hyprland.input.kb_layout") && SettingsStore.isAvailable("hyprland.general.gaps_in")) {
                stop();
                root.reopen();
            } else if (waited > 20000) {
                stop();
                root.fail(`Hyprland settings never became available: ${SettingsStore.unavailableReason("hyprland.input.kb_layout")}`);
            }
        }
    }

    Component {
        id: laterComponent
        Timer {
            id: later
            property var action: null
            onTriggered: {
                const action = later.action;
                later.destroy();
                action();
            }
        }
    }

    Component.onCompleted: {
        const component = Qt.createComponent(Qt.resolvedUrl("settings.qml"));
        if (component.status !== Component.Ready) {
            root.fail(`settings.qml failed to load: ${component.errorString()}`);
            return;
        }
        root.win = component.createObject(root, { width: 1100, height: 760 });
    }
}
