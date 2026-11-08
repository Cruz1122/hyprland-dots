//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
//@ pragma Env QT_QUICK_FLICKABLE_WHEEL_DECELERATION=10000

// Adjust this to make the app smaller or larger
//@ pragma Env QT_SCALE_FACTOR=1

import QtQuick
import QtQuick.Controls
import QtQuick.Window
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.services
import qs.modules.settings.core
import qs.modules.settings.backends
import qs.modules.settings.components

// Settings app (docs/settings.md). Harness contract: `pages` (registry page
// objects with `id`), writable `currentPage` index and `pageReady`.
ApplicationWindow {
    id: root

    readonly property var pages: SettingsRegistry.pages
    property int currentPage: 0
    readonly property bool pageReady: shell.host.ready
    property string pendingReveal: ""

    visible: true
    title: "illogical-impulse Settings"
    minimumWidth: 640
    minimumHeight: 480
    width: 1100
    height: 760
    color: Appearance.m3colors.m3background

    function pageIndex(pageId) {
        return root.pages.findIndex(p => p.id === pageId);
    }

    function openPage(pageId) {
        const index = root.pageIndex(pageId);
        if (index < 0)
            return false;
        root.currentPage = index;
        return true;
    }

    function reveal(key) {
        const pageId = SettingsRegistry.homePageId(key);
        if (!pageId)
            return false;
        root.pendingReveal = key;
        if (root.pageIndex(pageId) === root.currentPage)
            root.flushReveal();
        else
            root.openPage(pageId);
        return true;
    }

    function flushReveal() {
        if (!root.pendingReveal || !shell.host.ready)
            return;
        const key = root.pendingReveal;
        root.pendingReveal = "";
        // Rows lay out on the next frame; scroll once geometry exists.
        Qt.callLater(() => shell.host.currentItem?.scrollTo?.(key));
    }

    function showCurrentPage() {
        const page = root.pages[root.currentPage];
        if (!page || !Config.ready)
            return;
        shell.host.setSource(page.id, page.source);
        root.flushReveal();
    }

    onCurrentPageChanged: root.showCurrentPage()

    // Closing hides the window at once; the process quits after
    // SettingsStore.finish has reverted a pending risky change and the
    // backends have finished their queued writes and restores (they run
    // commands asynchronously). Opening the app again meanwhile cancels it.
    onClosing: close => {
        close.accepted = false;
        root.visible = false;
        SettingsStore.finish(() => Qt.quit());
    }

    // Shows the window, cancelling a quit in progress (onClosing).
    function present() {
        if (!root.visible) {
            SettingsStore.cancelFinish();
            root.visible = true;
        }
        root.requestActivate();
    }

    Component.onCompleted: {
        MaterialThemeLoader.reapplyTheme();
        Config.readWriteDelay = 150;
        const initialPage = Quickshell.env("II_SETTINGS_PAGE") || "";
        const initialKey = Quickshell.env("II_SETTINGS_KEY") || "";
        if (initialKey && SettingsRegistry.homePageId(initialKey)) {
            root.pendingReveal = initialKey;
            root.openPage(SettingsRegistry.homePageId(initialKey));
        } else if (initialPage) {
            root.openPage(initialPage);
        }
        root.showCurrentPage();
    }

    Connections {
        target: Config
        function onReadyChanged() {
            if (Config.ready)
                root.showCurrentPage();
        }
    }

    Shortcut {
        sequences: [StandardKey.Find]
        onActivated: shell.focusSearch()
    }

    Shortcut {
        sequence: "Ctrl+PgDown"
        onActivated: root.currentPage = (root.currentPage + 1) % root.pages.length
    }

    Shortcut {
        sequence: "Ctrl+PgUp"
        onActivated: root.currentPage = (root.currentPage - 1 + root.pages.length) % root.pages.length
    }

    IpcHandler {
        target: "settingsApp"

        function show(): void {
            root.present();
        }

        function open(pageId: string): void {
            root.openPage(pageId);
            root.present();
        }

        function reveal(key: string): void {
            root.reveal(key);
            root.present();
        }
    }

    SettingsShell {
        id: shell
        anchors.fill: parent
        currentPageId: root.pages[root.currentPage]?.id ?? ""
        showTitlebar: Config.options?.windows.showTitlebar ?? true
        centerTitle: Config.options?.windows.centerTitle ?? true
        onPageRequested: pageId => root.openPage(pageId)
        onRevealRequested: key => root.reveal(key)
        onCloseRequested: root.close()
    }
}
