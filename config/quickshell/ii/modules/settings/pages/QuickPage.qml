import QtQuick
import qs.modules.settings.components

// Every row here is an alias of a canonical entry on another page; the
// custom ones need the same delegates as their home page.
SettingsPage {
    pageId: "quick"

    customDelegates: ({
        "info.background.wallpaper": wallpaperCard,
        "action.appearance.darkMode": themeMode,
        "appearance.palette.type": scheme,
        "bar.position": barPosition
    })

    Component { id: wallpaperCard; SettingsWallpaperCard {} }
    Component { id: themeMode; SettingsThemeModeChoice {} }
    Component { id: scheme; SettingsSchemeChoice {} }
    Component { id: barPosition; SettingsBarPositionChoice {} }
}
