import QtQuick
import qs.services
import qs.modules.settings.core
import qs.modules.settings.components

// Animations page (docs/settings.md "Animations page"). The cards, the
// preset and the curve library are rows of their own (SettingsPage
// rowSources); this file adds the intro boxes and the [Apply Minimal] action.
SettingsPage {
    id: page

    pageId: "animations"

    infoValues: ({
        "info.animations.gameMode": Translation.tr("Active")
    })

    customDelegates: ({
        "info.animations.intro": intro
    })

    actions: ({
        // Through the preset row when it exists, so a custom state gets its Undo bar.
        "applyMinimalPreset": entry => {
            const presetRow = page.findItem(page.contentItem, "row:animation.preset");
            if (presetRow && typeof presetRow.applyPreset === "function")
                presetRow.applyPreset("minimal");
            else
                SettingsStore.write("animation.preset", "minimal");
        }
    })

    Component { id: intro; SettingsAnimationIntro {} }
}
