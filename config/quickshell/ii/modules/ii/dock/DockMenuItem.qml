import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

// One row of the dock's context menu, laid out like the tray menu entries.
RippleButton {
    id: root
    required property string symbol
    required property string label
    horizontalPadding: 12
    implicitWidth: contentItem.implicitWidth + horizontalPadding * 2
    implicitHeight: 36
    Layout.fillWidth: true
    colBackgroundHover: Appearance.colors.colLayer1Hover

    contentItem: RowLayout {
        anchors {
            verticalCenter: parent.verticalCenter
            left: parent.left
            right: parent.right
            leftMargin: root.horizontalPadding
            rightMargin: root.horizontalPadding
        }
        spacing: 10
        MaterialSymbol {
            iconSize: 20
            text: root.symbol
            color: Appearance.colors.colOnLayer0
        }
        StyledText {
            Layout.fillWidth: true
            text: root.label
            color: Appearance.colors.colOnLayer0
        }
    }
}
