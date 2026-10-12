import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.settings.components

SettingsButton {
    id: root

    property string description: ""
    height: Math.max(SettingsMetrics.controlHeight, tileColumn.implicitHeight + 20)

    contentItem: ColumnLayout {
        id: tileColumn
        anchors.centerIn: parent
        width: parent.width - 20
        spacing: 2

        StyledText {
            Layout.fillWidth: true
            text: root.label
            color: root.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
            horizontalAlignment: Text.AlignHCenter
        }

        StyledText {
            visible: root.description.length > 0
            Layout.fillWidth: true
            text: root.description
            color: root.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.smaller
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
        }
    }
}
