import qs.modules.common
import QtQuick

Text {
    id: root
    property real maximumWidth: 560
    // -1 left, 0 center, 1 right
    property int side: -1
    width: Math.min(implicitWidth, maximumWidth)
    wrapMode: Text.WordWrap
    horizontalAlignment: side < 0 ? Text.AlignLeft : side > 0 ? Text.AlignRight : Text.AlignHCenter
    color: Appearance.colors.colSubtext
    renderType: Text.CurveRendering
    lineHeight: 1.15
    font.family: Appearance.font.family.main
}
