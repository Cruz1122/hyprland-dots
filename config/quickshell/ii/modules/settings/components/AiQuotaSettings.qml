import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.settings.components

SettingsSection {
    id: root
    title: "Cuotas de IA y cuentas"
    icon: "account_circle"

    StyledText {
        Layout.fillWidth: true
        text: "Conecta desde el panel para mostrar consumos reales. ChatGPT y Go pueden usar tu fork de OpenCode; las credenciales manuales se guardan en el llavero, nunca en esta configuración."
        wrapMode: Text.Wrap
        font.pixelSize: 13
    }

    Repeater {
        model: ["codex", "opencode", "antigravity", "zed", "cursor", "claude"]
        delegate: SettingsCard {
            id: card
            required property string modelData
            readonly property var snapshot: AiQuotaUsage.snapshot(modelData)
            readonly property var choices: [{ id: "", alias: "Desactivado" }].concat(AiQuotaUsage.accountsFor(modelData))

            StyledText {
                Layout.fillWidth: true
                text: card.snapshot.name
                textFormat: Text.PlainText
                font.weight: Font.DemiBold
            }
            StyledText {
                Layout.fillWidth: true
                text: card.snapshot.status === "ready" ? (card.snapshot.identityVerified ? "Conectado · identidad verificada"
                    : "Conectado · identidad no verificada") : card.snapshot.message
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                font.pixelSize: 13
            }
            SettingsSelectRow {
                title: "Cuenta mostrada"
                visible: card.choices.length > 1
                model: card.choices
                textRole: "alias"
                currentIndex: Math.max(0, card.choices.findIndex(account => account.id === (AiQuotaUsage.data.selected?.[card.modelData] ?? "")))
                onActivated: index => {
                    const accountId = card.choices[index].id;
                    if (accountId) AiQuotaUsage.select(card.modelData, accountId);
                    else AiQuotaUsage.disable(card.modelData);
                }
            }
            RowLayout {
                SettingsActionButton {
                    text: "Conectar cuentas…"
                    enabled: AiQuotaUsage.available
                    // Connecting happens in the quota panel, fully in the GUI.
                    callback: () => {
                        AiQuotaUsage.requestConnection(card.modelData);
                        GlobalStates.openAiQuotaPanel("");
                    }
                }
                SettingsActionButton {
                    text: "Actualizar"
                    enabled: !!card.snapshot.accountId
                    callback: () => AiQuotaUsage.refresh(card.modelData)
                }
            }
        }
    }

    StyledText {
        Layout.fillWidth: true
        visible: AiQuotaUsage.operationError.length > 0
        text: AiQuotaUsage.operationError
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
    }
}
