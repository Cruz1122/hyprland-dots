import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.common
import qs.services

// Light/dark mode. The mode lives in the generated colors, not in a config
// key, so it is read from Appearance and changed by regenerating the
// palette from the current wallpaper (switchwall.sh, argv).
RowLayout {
    id: root

    readonly property bool inlineControl: true
    property var row: null

    SettingsChoiceButtons {
        enabled: root.row?.rowEnabled ?? true
        accessibleName: root.row?.label ?? ""
        currentValue: Appearance.m3colors.darkmode
        options: [
            { value: false, label: Translation.tr("Light"), icon: "light_mode" },
            { value: true, label: Translation.tr("Dark"), icon: "dark_mode" }
        ]
        onChosen: value => {
            if (value !== Appearance.m3colors.darkmode)
                Quickshell.execDetached([Directories.wallpaperSwitchScriptPath, "--mode", value ? "dark" : "light", "--noswitch"]);
        }
    }
}
