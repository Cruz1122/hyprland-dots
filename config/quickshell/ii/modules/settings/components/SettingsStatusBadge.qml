import QtQuick
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.settings.components

Rectangle {
    id: root

    property string text: ""
    property string status: "neutral"
    width: badgeText.implicitWidth + 20
    height: 28
    radius: height / 2
    color: root.status === "error" ? Appearance.colors.colErrorContainer : root.status === "success" ? Appearance.colors.colPrimaryContainer : Appearance.colors.colSecondaryContainer

    StyledText {
        id: badgeText
        anchors.centerIn: parent
        text: root.text
        color: root.status === "error" ? Appearance.colors.colOnErrorContainer : root.status === "success" ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSecondaryContainer
        font.pixelSize: Appearance.font.pixelSize.smaller
    }
}
