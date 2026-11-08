//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
//@ pragma Env QT_QUICK_FLICKABLE_WHEEL_DECELERATION=10000
//@ pragma Env QT_SCALE_FACTOR=1

// Offscreen render driver for the settings app. scripts/settings-harness/run.sh
// copies it next to settings.qml inside a sandboxed temporary tree; never run
// it against a live session.
//
// It instantiates the real settings.qml window instead of duplicating its page
// list, and relies only on this window contract:
//   pages: array      - an optional `id` per page names its screenshot
//   currentPage: int  - writable index of the visible page
//   pageReady: bool   - optional; false while the current page is loading
// Every result is logged as one "[harness:report] <json>" line that
// scripts/settings-harness/summarize.py turns into report.json.
import QtQuick
import Quickshell
import qs.modules.common
// Quickshell only generates the qs.* modules reachable from the root file's
// imports, so run.sh replaces the next line with every qs.* import of
// settings.qml.
// @harness-imports

ShellRoot {
    id: root

    readonly property string outDir: Quickshell.env("SHOT_DIR") || ""
    readonly property var sizes: root.parseSizes(Quickshell.env("SHOT_SIZES") || "1100x760")
    readonly property var pageFilter: (Quickshell.env("SHOT_PAGES") || "").split(",").map(s => s.trim()).filter(s => s.length > 0)
    readonly property int settleMs: parseInt(Quickshell.env("SHOT_SETTLE_MS") || "900")

    property var win: null
    property Item frame: null
    property var pageOrder: []
    property int sizeCursor: 0
    property int pageCursor: 0

    function parseSizes(text) {
        return text.split(/[ ,]+/).filter(s => s.length > 0).map(s => {
            const parts = s.toLowerCase().split("x").map(n => parseInt(n));
            return { w: parts[0], h: parts[1] };
        });
    }

    function report(payload) {
        console.info(`[harness:report] ${JSON.stringify(payload)}`);
    }

    // Qt.quit() is ignored until the root object finishes loading, so the
    // exit is deferred.
    function fail(message) {
        root.report({ type: "fatal", message: message });
        quitTimer.start();
    }

    function pageName(index) {
        const page = root.win.pages[index];
        if (page?.id)
            return String(page.id);
        const source = String(page?.component ?? `page${index}`);
        return source.split("/").pop().replace(/\.qml$/, "");
    }

    function computePageOrder() {
        const order = [];
        for (let i = 0; i < root.win.pages.length; i++) {
            if (root.pageFilter.length === 0 || root.pageFilter.includes(String(i)) || root.pageFilter.includes(root.pageName(i)))
                order.push(i);
        }
        return order;
    }

    // Moves every visual child of the window into an opaque frame: the window
    // contentItem is created in C++ and cannot be grabbed, and transparent
    // regions would otherwise come out blank.
    function wrapInFrame() {
        const content = root.win.contentItem;
        const children = [];
        for (const child of content.children)
            children.push(child);
        const frame = Qt.createQmlObject("import QtQuick; import QtQuick.Controls; Rectangle { property Item popupLayer: Overlay.overlay; anchors.fill: parent }", content, "harnessFrame");
        frame.color = Qt.binding(() => root.win.color);
        for (const child of children)
            child.parent = frame;
        root.frame = frame;
    }

    function isAncestor(ancestor, item) {
        for (let p = item.parent; p; p = p.parent) {
            if (p === ancestor)
                return true;
        }
        return false;
    }

    function collectRows(item, acc) {
        if (!item || !item.visible)
            return acc;
        const name = String(item.objectName ?? "");
        if (name.startsWith("row:") && item.width > 0 && item.height > 0) {
            const p = item.mapToItem(root.frame, 0, 0);
            acc.push({ key: name.slice(4), x: p.x, y: p.y, w: item.width, h: item.height, item: item });
        }
        for (const child of item.children)
            root.collectRows(child, acc);
        return acc;
    }

    // Rows are items whose objectName is "row:<settingKey>". Overlap ignores
    // ancestor/descendant pairs so composite rows may nest child rows.
    function layoutFindings() {
        const rows = root.collectRows(root.frame, []);
        const overlaps = [];
        for (let i = 0; i < rows.length; i++) {
            for (let j = i + 1; j < rows.length; j++) {
                const a = rows[i];
                const b = rows[j];
                if (root.isAncestor(a.item, b.item) || root.isAncestor(b.item, a.item))
                    continue;
                const ix = Math.min(a.x + a.w, b.x + b.w) - Math.max(a.x, b.x);
                const iy = Math.min(a.y + a.h, b.y + b.h) - Math.max(a.y, b.y);
                if (ix > 1 && iy > 1)
                    overlaps.push(`${a.key} x ${b.key}`);
            }
        }
        const overflowX = rows.filter(r => r.x < -1 || r.x + r.w > root.frame.width + 1).map(r => r.key);
        return { rows: rows.length, overlaps: overlaps, overflowX: overflowX, unavailable: root.unavailableByBackend(rows) };
    }

    // backend name -> number of visible rows whose backend is unavailable.
    // summarize.py uses it to prove the --hyprland-stub run really rendered
    // the Hyprland rows available instead of their "not running" state.
    function unavailableByBackend(rows) {
        const counts = {};
        for (const r of rows) {
            const e = SettingsStore.entry(r.key);
            if (e && !SettingsStore.isAvailable(r.key))
                counts[e.backend] = (counts[e.backend] ?? 0) + 1;
        }
        return counts;
    }

    // Visible children of the window overlay are open popups (tooltips,
    // menus, dialogs). A freshly loaded page must not open any.
    function openPopups() {
        const overlay = root.frame.popupLayer;
        if (!overlay)
            return -1;
        let count = 0;
        for (const child of overlay.children) {
            if (child.visible)
                count++;
        }
        return count;
    }

    function applySize() {
        const size = root.sizes[root.sizeCursor];
        root.win.width = size.w;
        root.win.height = size.h;
    }

    function start() {
        root.wrapInFrame();
        root.pageOrder = root.computePageOrder();
        if (root.pageOrder.length === 0) {
            root.fail(`no page matches SHOT_PAGES=${root.pageFilter.join(",")}`);
            return;
        }
        root.report({ type: "start", pages: root.pageOrder.map(i => root.pageName(i)), sizes: root.sizes.map(s => `${s.w}x${s.h}`) });
        root.applySize();
        root.visit();
    }

    function visit() {
        const index = root.pageOrder[root.pageCursor];
        const size = root.sizes[root.sizeCursor];
        root.report({ type: "visit", size: `${size.w}x${size.h}`, index: index, name: root.pageName(index) });
        root.win.currentPage = index;
        settleTimer.restart();
    }

    function capture() {
        if (root.win.pageReady === false) {
            settleTimer.restart();
            return;
        }
        const size = root.sizes[root.sizeCursor];
        const index = root.pageOrder[root.pageCursor];
        const name = root.pageName(index);
        const file = `${root.outDir}/${size.w}x${size.h}/${String(index).padStart(2, "0")}-${name}.png`;
        const findings = root.layoutFindings();
        const popups = root.openPopups();
        const started = root.frame.grabToImage(result => {
            const saved = result.saveToFile(file);
            root.report(Object.assign({ type: "page", size: `${size.w}x${size.h}`, index: index, name: name, file: file, saved: saved, openPopups: popups }, findings));
            root.advance();
        });
        if (!started)
            root.fail(`grabToImage refused for page ${name}`);
    }

    function advance() {
        if (root.pageCursor + 1 < root.pageOrder.length) {
            root.pageCursor++;
            root.visit();
            return;
        }
        if (root.sizeCursor + 1 < root.sizes.length) {
            root.sizeCursor++;
            root.pageCursor = 0;
            root.applySize();
            root.visit();
            return;
        }
        root.report({ type: "done" });
        Qt.quit();
    }

    Component.onCompleted: {
        const component = Qt.createComponent(Qt.resolvedUrl("settings.qml"));
        if (component.status !== Component.Ready) {
            root.fail(`settings.qml failed to load: ${component.errorString()}`);
            return;
        }
        root.win = component.createObject(root, { width: root.sizes[0].w, height: root.sizes[0].h });
        if (!root.win)
            root.fail("settings.qml window could not be created");
    }

    Timer {
        id: quitTimer
        interval: 200
        onTriggered: Qt.quit()
    }

    Timer {
        id: settleTimer
        interval: root.settleMs
        onTriggered: root.capture()
    }

    // Waits for the config file before the first page so every screenshot
    // reflects persisted values instead of schema defaults.
    Timer {
        id: bootTimer
        property int waited: 0
        interval: 100
        repeat: true
        running: true
        onTriggered: {
            waited += interval;
            if (!root.win) {
                stop();
                return;
            }
            if (!Config.ready) {
                if (waited > 20000) {
                    stop();
                    root.fail("Config.ready never became true");
                }
                return;
            }
            stop();
            startDelay.start();
        }
    }

    Timer {
        id: startDelay
        interval: root.settleMs * 2
        onTriggered: root.start()
    }
}
