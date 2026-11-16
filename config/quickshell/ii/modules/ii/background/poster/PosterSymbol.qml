import qs.modules.common
import QtQuick

// A Material Symbol at poster size.
PosterInk {
    id: root
    property real size: 240
    color: Appearance.colors.colPrimary
    // Symbols are drawn centered in their square; the measured ink box is
    // unreliable for this font and would shift each one differently.
    tight: false
    font {
        family: Appearance.font.family.iconMaterial
        pixelSize: size
        hintingPreference: Font.PreferNoHinting
        // Outlined on purpose: at this size the filled variants show seams
        // where the fill contour meets the outline.
        variableAxes: ({ "FILL": 0, "wght": 300, "opsz": 48 })
    }
}
