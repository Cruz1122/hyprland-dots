import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs.modules.settings.core

// "Keep changes?" bar for risky settings. Anchor it at the bottom of the
// content; it slides in while SettingsStore.pendingConfirmation is set.
Rectangle {
    id: root

    readonly property var pending: SettingsStore.pendingConfirmation
    readonly property bool shown: root.pending !== null

    objectName: "settingsConfirmBar"
    implicitWidth: Math.min(layout.implicitWidth + 36, 640)
    implicitHeight: layout.implicitHeight + 20
    radius: SettingsMetrics.cardRadius
    color: Appearance.colors.colTooltip
    visible: opacity > 0
    opacity: root.shown ? 1 : 0
    Accessible.role: Accessible.AlertMessage
    Accessible.name: Translation.tr("Keep changes?")

    Behavior on opacity {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    RowLayout {
        id: layout
        anchors {
            left: parent.left
            right: parent.right
            verticalCenter: parent.verticalCenter
            leftMargin: 20
            rightMargin: 12
        }
        spacing: 12

        MaterialSymbol {
            text: "timer"
            iconSize: 22
            color: Appearance.colors.colOnTooltip
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            StyledText {
                text: Translation.tr("Keep changes?")
                font.weight: Font.Medium
                color: Appearance.colors.colOnTooltip
            }

            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Reverting in %1 s").arg(root.pending?.secondsLeft ?? 0)
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colOnTooltip
                opacity: 0.8
            }
        }

        SettingsButton {
            kind: "text"
            text: Translation.tr("Revert")
            onClicked: SettingsStore.revert()
        }

        SettingsButton {
            kind: "filled"
            text: Translation.tr("Keep")
            onClicked: SettingsStore.confirm()
        }
    }
}
