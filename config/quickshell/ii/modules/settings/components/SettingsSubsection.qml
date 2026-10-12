import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

ColumnLayout {
    id: root

    property string title: ""
    property string text: ""
    property string description: ""
    property string tooltip: ""
    default property alias contentData: subsectionContent.data

    Layout.fillWidth: true
    spacing: 6

    RowLayout {
        Layout.fillWidth: true
        spacing: 6

        StyledText {
            Layout.fillWidth: true
            text: root.title || root.text
            color: Appearance.colors.colOnLayer1
            font.pixelSize: Appearance.font.pixelSize.small
            font.weight: Font.Medium
        }

        SettingsHelpButton {
            visible: root.description.length > 0 || root.tooltip.length > 0
            helpText: root.description || root.tooltip
        }
    }

    ColumnLayout {
        id: subsectionContent
        Layout.fillWidth: true
        spacing: SettingsMetrics.compactRowSpacing
    }
}
