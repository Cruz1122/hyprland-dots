import QtQuick
import Quickshell
import qs.modules.common
import qs.modules.settings.components

SettingsPage {
    pageId: "appearance"

    customDelegates: ({
        "action.appearance.darkMode": themeMode,
        "appearance.palette.type": scheme
    })

    // Wallpaper theming is otherwise applied only by the next wallpaper
    // change; --noswitch regenerates it from the current one.
    actions: ({
        applyTheme: entry => Quickshell.execDetached([Directories.wallpaperSwitchScriptPath, "--noswitch"])
    })

    Component { id: themeMode; SettingsThemeModeChoice {} }
    Component { id: scheme; SettingsSchemeChoice {} }
}
