import QtQuick
import "IridescentPalette.js" as Palette

// Animated iridescent overlay for bar pills. Declare it as the first child of
// the pill Rectangle so it paints above the base color and below the content.
Rectangle {
    id: root
    property bool active: false
    // Optional blend toward a status color (e.g. resource severity -> error).
    property color tint: "transparent"
    property real tintAmount: 0
    property real phase: 0

    // Lightness stays >= 0.8 so the dark pill ink keeps >= 4.5:1 contrast on
    // every hue, including blue (the darkest pastel).
    function shade(position) {
        const hue = Palette.hue(phase, position);
        const sheen = 0.8 + 0.07 * (0.5 + 0.5 * Math.sin((phase * 2 + position) * 2 * Math.PI));
        const base = Qt.hsla(hue, 0.9, sheen, 1);
        const amount = Math.max(0, Math.min(1, tintAmount));
        return Qt.rgba(base.r + (tint.r - base.r) * amount,
            base.g + (tint.g - base.g) * amount,
            base.b + (tint.b - base.b) * amount, 1);
    }

    anchors.fill: parent
    radius: height / 2
    opacity: active ? 1 : 0
    visible: opacity > 0

    gradient: Gradient {
        orientation: Gradient.Horizontal
        GradientStop { position: 0.0; color: root.shade(0.0) }
        GradientStop { position: 0.25; color: root.shade(0.25) }
        GradientStop { position: 0.5; color: root.shade(0.5) }
        GradientStop { position: 0.75; color: root.shade(0.75) }
        GradientStop { position: 1.0; color: root.shade(1.0) }
    }

    NumberAnimation on phase {
        running: root.visible
        from: 0
        to: 1
        duration: 6000
        loops: Animation.Infinite
    }

    Behavior on opacity {
        NumberAnimation { duration: 900; easing.type: Easing.InOutQuad }
    }
}
