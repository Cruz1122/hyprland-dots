import QtQuick
import qs.modules.settings.components

SettingsPage {
    pageId: "services"

    customDelegates: ({
        "info.services.aiQuotas": aiQuotas
    })

    Component {
        id: aiQuotas
        AiQuotaSettings {}
    }
}
