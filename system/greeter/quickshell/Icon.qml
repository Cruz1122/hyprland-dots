import QtQuick

// Material Symbols glyph, as the shell's MaterialSymbol draws it.
Text {
    property real size: 22
    font.family: Theme.iconFont
    font.pixelSize: size
    color: Theme.ink
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
    renderType: Text.NativeRendering
}
