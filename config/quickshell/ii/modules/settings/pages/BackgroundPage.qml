import QtQuick
import qs.modules.settings.components

SettingsPage {
    pageId: "background"

    customDelegates: ({
        "info.background.wallpaper": wallpaperCard
    })

    Component { id: wallpaperCard; SettingsWallpaperCard {} }
}
