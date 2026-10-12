import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.settings.components

ColumnLayout {
    id: root

    property string title: ""
    property string description: ""
    Layout.fillWidth: true
    spacing: 4

    StyledText {
        Layout.fillWidth: true
        text: root.title
        color: Appearance.colors.colOnLayer0
        font.family: Appearance.font.family.title
        font.pixelSize: Appearance.font.pixelSize.title
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
