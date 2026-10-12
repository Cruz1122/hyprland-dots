import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.settings.components

ColumnLayout {
    id: root

    property string title: ""
    property string description: ""
    property string icon: ""
    default property alias contentData: sectionCard.cardData

    Layout.fillWidth: true
    spacing: 8

    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        MaterialSymbol {
            visible: root.icon.length > 0
            text: root.icon
            iconSize: Appearance.font.pixelSize.large
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            StyledText {
                Layout.fillWidth: true
                text: root.title
                color: Appearance.colors.colOnLayer0
                font.pixelSize: Appearance.font.pixelSize.larger
                font.weight: Font.Medium
            }

            StyledText {
                visible: root.description.length > 0
                Layout.fillWidth: true
                text: root.description
                color: Appearance.colors.colSubtext
                wrapMode: Text.WordWrap
            }
        }
    }

    SettingsCard {
        id: sectionCard
    }
}
