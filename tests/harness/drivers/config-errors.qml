//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
//@ pragma Env QT_SCALE_FACTOR=1

// Harness driver (run.sh --strict [--hyprland-stub] --driver): the Advanced
// page's "Hyprland configuration errors" row. It opens the page, waits for the
// row's first check (`hyprctl -j configerrors`, answered by the stub from
// HYPRCTL_CONFIGERRORS), reports what the row shows, presses "Check again" and
// reports again. tests/test_hyprland_e14.py runs it with each fixture and
// without the stub (Hyprland not running) and checks the reports.
import QtQuick
import Quickshell
import qs.modules.common
// @harness-imports

ShellRoot {
    id: root

    property var win: null
    property var row: null

    function report(payload) {
        console.info(`[harness:report] ${JSON.stringify(payload)}`);
    }

    function finish() {
        root.report({ type: "done" });
        quitTimer.start();
    }

    function fatal(message) {
        root.report({ type: "fatal", message: message });
        root.finish();
    }

    function walk(item, visit) {
        if (!item)
            return;
        visit(item);
        for (const child of item.children)
            root.walk(child, visit);
    }

    function find(item, name) {
        let found = null;
        root.walk(item, i => {
            if (!found && i.objectName === name)
                found = i;
        });
        return found;
    }

    function pageItem(id) {
        let found = null;
        root.walk(root.win.contentItem, item => {
            if (!found && item.pageId === id && item.contentY !== undefined)
                found = item;
        });
        return found;
    }

    function waitFor(test, timeoutMs, done) {
        pollComponent.createObject(root, { deadline: Date.now() + timeoutMs, test: test, done: done }).start();
    }

    function state(step) {
        const errs = root.row;
        const text = root.find(errs, "configErrorsText");
        const button = root.find(errs, "configErrorsCheck");
        root.report({
            type: "state",
            step: step,
            status: errs.status,
            summary: String(root.find(errs, "configErrorsSummary")?.text ?? ""),
            errors: errs.errors,
            hidden: errs.hidden,
            textShown: !!text && text.visible && text.parent.visible,
            text: text ? String(text.text) : "",
            selectable: !!text && text.selectByMouse && text.readOnly,
            wraps: !!text && text.wrapMode !== TextEdit.NoWrap,
            textInside: !!text && text.width <= text.parent.width,
            buttonShown: !!button && button.visible
        });
    }

    Component.onCompleted: {
        const component = Qt.createComponent(Qt.resolvedUrl("settings.qml"));
        if (component.status !== Component.Ready)
            return root.fatal(`settings.qml failed to load: ${component.errorString()}`);
        root.win = component.createObject(root, { width: 1100, height: 760 });
        root.waitFor(() => root.win.pageReady, 20000, ready => {
            if (!ready)
                return root.fatal("the first page never became ready");
            root.win.openPage("advanced");
            root.waitFor(() => root.win.pageReady && root.pageItem("advanced") !== null
                && root.find(root.pageItem("advanced"), "configErrors") !== null, 10000, ok => {
                if (!ok)
                    return root.fatal("the configuration errors row never appeared");
                root.row = root.find(root.pageItem("advanced"), "configErrors");
                root.waitFor(() => root.row.status !== "checking", 10000, () => root.afterFirst());
            });
        });
    }

    function afterFirst() {
        root.state("open");
        const button = root.find(root.row, "configErrorsCheck");
        if (!button?.visible)
            return root.finish();
        button.clicked();
        root.report({ type: "pressed", status: root.row.status });
        root.waitFor(() => root.row.status !== "checking", 10000, () => {
            root.state("again");
            root.finish();
        });
    }

    Timer {
        id: quitTimer
        interval: 200
        onTriggered: Qt.quit()
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
                let ok = false;
                try {
                    ok = !!poll.test();
                } catch (error) {
                    ok = false;
                }
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
