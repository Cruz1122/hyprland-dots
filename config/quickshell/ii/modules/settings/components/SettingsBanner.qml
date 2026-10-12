import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.settings.components

Rectangle {
    id: root

    property alias text: message.text
    property alias icon: icon.text
    property alias materialIcon: icon.text
    default property alias actionData: actionRow.data
    Layout.fillWidth: true
    height: content.implicitHeight + 24
    radius: SettingsMetrics.controlRadius
    color: Appearance.colors.colPrimaryContainer

    RowLayout {
        id: content
        anchors.fill: parent
        anchors.margins: 12
        spacing: 10

        MaterialSymbol {
            id: icon
            text: "info"
            Layout.alignment: Qt.AlignTop
            color: Appearance.colors.colOnPrimaryContainer
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8

            StyledText {
                id: message
                Layout.fillWidth: true
                color: Appearance.colors.colOnPrimaryContainer
                wrapMode: Text.WordWrap
            }

            RowLayout {
                id: actionRow
                visible: children.length > 0
                Layout.fillWidth: true
            }
        }
    }
}
