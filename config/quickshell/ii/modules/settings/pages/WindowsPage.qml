import QtQuick
import Quickshell
import qs.modules.common
import qs.modules.common.functions
import qs.services
import qs.modules.settings.components
import "WindowsLogic.js" as WindowsLogic
import "../components/WindowPreviewLogic.js" as PreviewLogic

SettingsPage {
    id: windowsPage
    pageId: "windows"

    // Row the preview highlights: the hovered one, else the one with focus.
    property string hoveredKey: ""
    readonly property string focusedKey: WindowsLogic.rowKeyOf(windowsPage.focusItem)
    readonly property string highlightKey: windowsPage.hoveredKey.length > 0 ? windowsPage.hoveredKey : windowsPage.focusedKey

    actions: ({
        openRules: entry => Quickshell.execDetached(["xdg-open", `${FileUtils.trimFileProtocol(Directories.config)}/hypr/custom/rules.lua`])
    })
    infoValues: ({
        "info.windows.gameMode": Translation.tr("Active")
    })
    customDelegates: ({
        "info.windows.preview": layoutPreview,
        "info.windows.effectsPreview": effectsPreview
    })

    // Rows are created with the page; their hover is followed once they exist.
    Component.onCompleted: Qt.callLater(() => {
        for (const key of Object.keys(PreviewLogic.KEY_PARTS)) {
            const row = windowsPage.findItem(windowsPage.contentItem, "row:" + key);
            if (!row)
                continue;
            row.hoveredChanged.connect(() => {
                windowsPage.hoveredKey = WindowsLogic.nextHoveredKey(windowsPage.hoveredKey, key, row.hovered);
            });
        }
    })

    Component {
        id: layoutPreview
        SettingsWindowPreview {
            showMagnifier: true
            highlightKey: windowsPage.highlightKey
        }
    }

    Component {
        id: effectsPreview
        SettingsWindowPreview {
            id: effectsPreviewItem
            objectName: "windowEffectsPreview"
            showMagnifier: false
            accessibleName: Translation.tr("Effects preview")
            accessibleDescription: effectsPreviewItem.effectsSummary
            highlightKey: windowsPage.highlightKey
        }
    }
}
