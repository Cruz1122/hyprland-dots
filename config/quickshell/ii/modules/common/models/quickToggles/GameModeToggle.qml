import QtQuick
import Quickshell.Io
import qs.services

QuickToggleModel {
    id: root

    // Overrides Game Mode writes to shellOverrides/main.lua. That file is
    // loaded last by hyprland.lua, so these win over the settings app's
    // custom/shell-settings.lua while Game Mode is on, and removing them
    // restores the user's values.
    readonly property var overrides: ({
            "animations:enabled": 0,
            "decoration:shadow:enabled": 0,
            "decoration:blur:enabled": 0,
            "general:gaps_in": 0,
            "general:gaps_out": 0,
            "general:border_size": 1,
            "decoration:rounding": 0,
            "general:allow_tearing": 1
        })

    name: Translation.tr("Game mode")
    icon: "gamepad"
    tooltipText: Translation.tr("Game mode")
    // Game Mode's own override is the source of truth. Deriving the state from
    // the effective animations:enabled made it look active whenever the
    // settings app turned animations off.
    toggled: overridesFile.gameModeActive

    mainAction: () => {
        if (root.toggled)
            HyprlandConfig.resetMany(Object.keys(root.overrides));
        else
            HyprlandConfig.setMany(root.overrides);
    }

    // A file watch cannot see the file being created, and Hyprland reloads
    // right after Game Mode rewrites it, so every reload refreshes too.
    Connections {
        target: HyprlandConfig
        function onReloaded() {
            overridesFile.reload();
        }
    }

    FileView {
        id: overridesFile

        property bool gameModeActive: false

        function refresh() {
            overridesFile.gameModeActive = /^\s*hl\.config\(\{\s*animations\s*=\s*\{\s*enabled\s*=/m.test(overridesFile.text());
        }

        path: HyprlandConfig.shellOverridesPath
        watchChanges: true
        onFileChanged: reload()
        onLoaded: refresh()
        onLoadFailed: gameModeActive = false
    }
}
