import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import "AiQuotaPresentation.js" as Quota

Item {
    id: root
    required property Item hoverTarget
    readonly property bool active: loader.active
    readonly property var snapshot: hoverTarget.quotaSnapshot
    // Drives the relative reset countdown so it stays current while hovered.
    property double clockMs: Date.now()

    Timer {
        interval: 30000
        repeat: true
        running: root.active
        onTriggered: root.clockMs = Date.now()
    }

    LazyLoader {
        id: loader
        active: root.hoverTarget.popupShowing && root.hoverTarget.visible

        component: PanelWindow {
            id: popup
            screen: root.hoverTarget.QsWindow.window?.screen
            color: "transparent"
            anchors.left: true
            anchors.top: !Config.options.bar.bottom
            anchors.bottom: Config.options.bar.bottom
            exclusionMode: ExclusionMode.Ignore
            exclusiveZone: 0
            implicitWidth: 360
            implicitHeight: Math.min(content.implicitHeight + 28,
                Math.max(160, (screen?.height ?? 1080) - Appearance.sizes.barHeight - 24))
            margins {
                top: Appearance.sizes.barHeight
                bottom: Appearance.sizes.barHeight
                left: Math.max(8, Math.min((screen?.width ?? 1920) - popup.width - 8,
                    root.hoverTarget.QsWindow.mapFromItem(root.hoverTarget,
                        (root.hoverTarget.width - popup.width) / 2, 0).x))
            }
            WlrLayershell.namespace: "quickshell:ai-quota"
            WlrLayershell.layer: WlrLayer.Overlay

            Rectangle {
                anchors.fill: parent
                radius: Appearance.rounding.small
                color: Appearance.m3colors.m3surfaceContainer
                border.color: Appearance.colors.colLayer0Border
                border.width: 1

                HoverHandler {
                    onHoveredChanged: root.hoverTarget.popupHovered = hovered
                }

                ScrollView {
                    id: scroll
                    anchors.fill: parent
                    anchors.margins: 14
                    clip: true
                    contentWidth: availableWidth

                ColumnLayout {
                    id: content
                    width: scroll.availableWidth
                    spacing: 8

                    StyledText {
                        Layout.fillWidth: true
                        text: root.snapshot.name
                        textFormat: Text.PlainText
                        font.weight: Font.DemiBold
                    }
                    StyledText {
                        Layout.fillWidth: true
                        visible: text.length > 0
                        text: root.snapshot.alias ?? ""
                        textFormat: Text.PlainText
                        color: Appearance.colors.colOnSurfaceVariant
                        wrapMode: Text.Wrap
                    }
                    StyledText {
                        Layout.fillWidth: true
                        visible: !!root.snapshot.accountId
                        text: root.snapshot.identityVerified ? "Identidad verificada"
                            : root.snapshot.source?.endsWith("-cli")
                                ? "Sesión activa del cliente · identidad no verificada"
                                : "Alias local · identidad no verificada"
                        font.pixelSize: 12
                        wrapMode: Text.Wrap
                        color: Appearance.colors.colOnSurfaceVariant
                    }
                    StyledText {
                        Layout.fillWidth: true
                        visible: root.snapshot.status !== "ready"
                        text: root.snapshot.message ?? "Cuota no disponible"
                        textFormat: Text.PlainText
                        wrapMode: Text.Wrap
                    }

                    Repeater {
                        model: root.snapshot.windows ?? []
                        delegate: ColumnLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: 3
                            StyledText {
                                Layout.fillWidth: true
                                text: modelData.label
                                textFormat: Text.PlainText
                                wrapMode: Text.Wrap
                                color: "#f6d77a"
                                font.weight: Font.Bold
                                font.variableAxes: Object.assign({}, Appearance.font.variableAxes.main, { "wght": 700 })
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: modelData.usedAmount !== null && modelData.usedAmount !== undefined
                                    ? "USD " + modelData.usedAmount.toFixed(2) + " / "
                                        + (modelData.limitAmount !== null ? modelData.limitAmount.toFixed(2) : "—")
                                    : modelData.usedPercent !== null && modelData.usedPercent !== undefined
                                        ? Math.round(100 - modelData.usedPercent) + "% libre · "
                                            + Math.round(modelData.usedPercent) + "% usado"
                                        : "Cuota no disponible"
                                font.pixelSize: 13
                            }
                            StyledText {
                                Layout.fillWidth: true
                                visible: text.length > 0
                                // Relative time left, never an absolute instant or timezone.
                                text: Quota.resetCountdown(modelData.resetsAt, root.clockMs)
                                    ?? modelData.resetText ?? ""
                                textFormat: Text.PlainText
                                color: Appearance.colors.colOnSurfaceVariant
                                font.pixelSize: 12
                                wrapMode: Text.Wrap
                            }
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        visible: !!root.snapshot.observedAt
                        text: (root.snapshot.stale ? "Dato desactualizado · " : "Actualizado · ")
                            + Math.max(0, Math.floor((Date.now() / 1000 - (root.snapshot.observedAt ?? 0)) / 60)) + " min"
                        font.pixelSize: 12
                        color: Appearance.colors.colOnSurfaceVariant
                    }
                    RowLayout {
                        Button {
                            text: "Gestionar cuentas"
                            onClicked: AiQuotaUsage.manage(root.hoverTarget.providerId)
                        }
                        Button {
                            text: "Actualizar"
                            enabled: !!root.snapshot.accountId
                            onClicked: AiQuotaUsage.refresh(root.hoverTarget.providerId)
                        }
                    }
                }
                }
            }
            Component.onDestruction: root.hoverTarget.popupHovered = false
        }
    }
}
