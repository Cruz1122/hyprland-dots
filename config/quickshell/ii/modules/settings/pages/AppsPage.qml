import QtQuick
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions
import qs.modules.settings.components
import "AppsLogic.js" as AppsLogic

SettingsPage {
    id: root
    pageId: "apps"

    readonly property string hyprDir: FileUtils.trimFileProtocol(Directories.config) + "/hypr"
    property var baseVariables: ({})
    property var customVariables: ({})

    infoValues: AppsLogic.infoValues(AppsLogic.merge(root.baseVariables, root.customVariables), "info.apps.")

    // Read-only: the user edits custom/variables.lua; this page only shows the
    // effective value. Both files are optional.
    FileView {
        path: root.hyprDir + "/hyprland/variables.lua"
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.baseVariables = AppsLogic.parseVariables(text())
        onLoadFailed: root.baseVariables = ({})
    }

    FileView {
        path: root.hyprDir + "/custom/variables.lua"
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.customVariables = AppsLogic.parseVariables(text())
        onLoadFailed: root.customVariables = ({})
    }
}
