//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
//@ pragma Env QT_SCALE_FACTOR=1

// Harness driver (run.sh --driver): every visible drop-down shows some text
// and every segmented choice has an option selected, on every page. A value
// outside the choices used to leave an empty box (Notifications > Monitor
// before a monitor was chosen). Rows whose backend is unavailable in the
// sandbox (Hyprland, audio, displays) are skipped: they have no value here.
// Reports one "blank" event per offending control, then "done".
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

    function walk(item, visit) {
        if (!item)
            return;
        visit(item);
        for (const child of item.children)
            root.walk(child, visit);
    }

    function rowKey(item) {
        for (let p = item; p; p = p.parent) {
            const name = String(p.objectName);
            if (name.startsWith("row:"))
                return name.slice(4);
        }
        return "";
    }

    function pageItem(id) {
        let found = null;
        root.walk(root.win.contentItem, item => {
            if (!found && item.pageId === id && item.contentY !== undefined)
                found = item;
        });
        return found;
    }

    function visibleIn(item, page) {
        for (let p = item; p && p !== page; p = p.parent) {
            if (!p.visible)
                return false;
        }
        return true;
    }

    function scan(id) {
        const page = root.pageItem(id);
        if (!page) {
            root.report({ type: "blank", page: id, row: "", control: "page not found" });
            return;
        }
        root.walk(page, item => {
            const combo = item.popup !== undefined && typeof item.currentIndex === "number" && item.displayText !== undefined;
            const segmented = !combo && Array.isArray(item.options) && item.options.length > 0 && typeof item.currentIndex === "number";
            if (!combo && !segmented)
                return;
            const blank = combo ? String(item.displayText).length === 0 : item.currentIndex < 0;
            const key = root.rowKey(item);
            if (blank && key.length > 0 && SettingsStore.isAvailable(key) && root.visibleIn(item, page))
                root.report({ type: "blank", page: id, row: key, control: combo ? "drop-down" : "segmented" });
        });
    }

    function step(index) {
        const pages = root.win.pages;
        if (index >= pages.length) {
            root.report({ type: "done" });
            Qt.quit();
            return;
        }
        root.win.openPage(pages[index].id);
        laterComponent.createObject(root, { interval: 700, action: () => {
            root.scan(pages[index].id);
            root.step(index + 1);
        } }).start();
    }

    Timer {
        interval: 100
        repeat: true
        running: root.win !== null
        property int waited: 0
        onTriggered: {
            waited += interval;
            if (root.win.pageReady) {
                stop();
                root.step(0);
            } else if (waited > 20000) {
                stop();
                root.report({ type: "fatal", message: "the first page never became ready" });
                Qt.quit();
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
            root.report({ type: "fatal", message: `settings.qml failed to load: ${component.errorString()}` });
            Qt.quit();
            return;
        }
        root.win = component.createObject(root, { width: 1100, height: 760 });
    }
}
