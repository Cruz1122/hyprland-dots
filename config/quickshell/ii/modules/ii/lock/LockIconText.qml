import QtQuick
import qs.modules.common
import qs.modules.common.widgets

// Status readout for the lock screen corner pill: icon and short text.
Row {
    id: root
    required property string icon
    required property string text
    property color color: Appearance.colors.colSubtext
    spacing: 6

    MaterialSymbol {
        anchors.verticalCenter: parent.verticalCenter
        fill: 1
        text: root.icon
        iconSize: Appearance.font.pixelSize.huge
        color: root.color
    }
    StyledText {
        anchors.verticalCenter: parent.verticalCenter
        text: root.text
        color: root.color
    }
}
