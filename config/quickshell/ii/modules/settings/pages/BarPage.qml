import QtQuick
import qs.modules.settings.components

SettingsPage {
    pageId: "bar"

    customDelegates: ({
        "bar.position": barPosition,
        "bar.screenList": screens
    })

    Component { id: barPosition; SettingsBarPositionChoice {} }
    Component { id: screens; SettingsScreenChoice {} }
}
