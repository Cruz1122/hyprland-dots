import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.settings.components

Rectangle {
    id: root

    property real padding: SettingsMetrics.cardPadding
    property real contentSpacing: SettingsMetrics.cardSpacing
    default property alias cardData: cardColumn.data

    Layout.fillWidth: true
    height: cardColumn.implicitHeight + root.padding * 2
    radius: SettingsMetrics.cardRadius
    color: Appearance.colors.colLayer1
    border.width: 1
    border.color: Appearance.m3colors.m3outlineVariant

    ColumnLayout {
        id: cardColumn
        anchors.fill: parent
        anchors.margins: root.padding
        spacing: root.contentSpacing
    }
}
