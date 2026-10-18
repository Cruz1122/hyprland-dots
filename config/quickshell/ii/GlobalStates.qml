import qs.modules.common
import qs.services
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
pragma Singleton
pragma ComponentBehavior: Bound

Singleton {
    id: root
    property bool barOpen: true
    property bool authenticatorOpen: false
    property bool authenticatorPresented: false
    property string authenticatorScreenName: ""
    // QR payload is ephemeral and consumed/cleared by the authenticator controller.
    property string authenticatorQrPayload: ""
    property string authenticatorQrStatus: ""
    property string authenticatorQrScreenName: ""
    property int authenticatorQrCaptureRevision: 0

    // Keep one monitor for the entire presentation, including a reversed exit.
    function openAuthenticator(screenName: string): void {
        if (root.screenLocked) return;
        if (!root.authenticatorPresented) {
            const name = screenName || Hyprland.focusedMonitor?.name || Quickshell.screens[0]?.name;
            if (!name) return;
            root.authenticatorScreenName = name;
        }
        root.authenticatorOpen = true;
    }

    function toggleAuthenticator(): void {
        if (root.authenticatorOpen) root.authenticatorOpen = false;
        else root.openAuthenticator("");
    }

    property bool crosshairOpen: false
    property bool displayControlOpen: false
    property bool sidebarLeftOpen: false
    property bool sidebarRightOpen: false
    property bool mediaControlsOpen: false
    property bool osdBrightnessOpen: false
    property bool osdVolumeOpen: false
    property bool oskOpen: false
    property bool overlayOpen: false
    property bool overviewOpen: false
    property bool regionSelectorOpen: false
    property bool searchOpen: false
    property bool screenLocked: false
    property bool screenLockContainsCharacters: false
    property bool screenUnlockFailed: false
    property bool screenTranslatorOpen: false
    property bool sessionOpen: false
    property bool superDown: false
    property bool superReleaseMightTrigger: true
    property bool wallpaperSelectorOpen: false
    property bool workspaceShowNumbers: false

    onSidebarRightOpenChanged: {
        if (GlobalStates.sidebarRightOpen) {
            Notifications.timeoutAll();
            Notifications.markAllRead();
        }
    }

    GlobalShortcut {
        name: "workspaceNumber"
        description: "Hold to show workspace numbers, release to show icons"

        onPressed: {
            root.superDown = true
        }
        onReleased: {
            root.superDown = false
        }
    }
}
