import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import "ResourcePresentation.js" as Presentation

Rectangle {
    id: root
    property var resource: null
    readonly property color gold: "#F6D77A"
    readonly property color ink: "#4A3900"
    readonly property var blended: Presentation.mix(gold, Appearance.m3colors.m3error,
        Presentation.severity(resource?.value ?? 0))
    readonly property color foreground: Presentation.foreground(color, ink)

    implicitWidth: 58
    implicitHeight: 18
    radius: height / 2
    color: resource ? Qt.rgba(blended.r, blended.g, blended.b, 1) : Appearance.colors.colSecondaryContainer
    Accessible.role: Accessible.StaticText
    Accessible.name: resource ? `${resource.id} ${Math.round(resource.value * 100)}%` : "--"

    Behavior on color {
        ColorAnimation { duration: 300; easing.type: Easing.InOutQuad }
    }

    RowLayout {
        anchors.centerIn: parent
        height: parent.height
        spacing: 2

        MaterialSymbol {
            text: root.resource?.icon ?? "hourglass_empty"
            // Dense resource glyphs need a small optical correction relative
            // to the clock/bolt symbols to occupy the same visual area.
            iconSize: Appearance.font.pixelSize.smaller + 2
            fill: 1
            color: root.foreground
            Layout.alignment: Qt.AlignVCenter
            Layout.leftMargin: 2
            Layout.rightMargin: 2
        }
        StyledText {
            text: root.resource ? Math.round(root.resource.value * 100) : "--"
            color: root.foreground
            font.pixelSize: 13
            font.weight: Font.Medium
            verticalAlignment: Text.AlignVCenter
            Layout.alignment: Qt.AlignVCenter
        }
    }
}
