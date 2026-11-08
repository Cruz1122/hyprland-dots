import Quickshell
import qs.modules.common
import qs.modules.common.functions
import qs.services
import qs.modules.settings.components

SettingsPage {
    pageId: "windows"

    actions: ({
        openRules: entry => Quickshell.execDetached(["xdg-open", `${FileUtils.trimFileProtocol(Directories.config)}/hypr/custom/rules.lua`])
    })
    infoValues: ({
        "info.windows.gameMode": Translation.tr("Active")
    })
}
