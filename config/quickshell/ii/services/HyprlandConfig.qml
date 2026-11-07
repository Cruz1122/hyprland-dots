pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland

import qs.modules.common
import qs.modules.common.functions

/**
 * Configs Hyprland
 */
Singleton {
    id: root
    
    signal reloaded()

    readonly property string configuratorScriptPath: Quickshell.shellPath("scripts/hyprland/hyprconfigurator.py")
    readonly property string shellOverridesPath: FileUtils.trimFileProtocol(`${Directories.config}/hypr/hyprland/shellOverrides/main.lua`)

    // argv only: keys and values reach the script as separate items, never through a shell.
    function run(args: var) {
        Quickshell.execDetached([root.configuratorScriptPath, "--file", root.shellOverridesPath].concat(args))
    }

    function set(key: string, value: var) {
        root.run(["--set", key, String(value)])
    }

    function setMany(entries: var) {
        let args = []
        for (let key in entries) {
            args.push("--set", key, String(entries[key]))
        }
        if (args.length > 0)
            root.run(args)
    }

    function reset(key: string) {
        root.run(["--reset", key])
    }

    function resetMany(keys: list<string>) {
        let args = []
        for (let i = 0; i < keys.length; i++) {
            args.push("--reset", keys[i])
        }
        if (args.length > 0)
            root.run(args)
    }

    Connections {
        target: Hyprland

        function onRawEvent(event) {
            if (event.name == "configreloaded") {
                root.reloaded()
            }
        }
    }
}
