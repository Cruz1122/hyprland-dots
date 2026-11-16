import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.bar
import QtQuick
import QtQuick.Layouts

// Quick action: icon over a short label; `active` highlights a live state.
RippleButton {
    id: tile
    required property string iconName
    required property string label
    property string tooltip: label
    property bool active: false
    property bool alert: false
    // Paints the tile with the bar pills' iridescent palette.
    property bool iridescent: false
    property var triggerAction: null
    readonly property color ink: alert ? Appearance.m3colors.m3onError
        : iridescent ? "#1B1B1F"
        : active ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1
    Layout.fillWidth: true
    // Equal widths whatever the label length.
    Layout.preferredWidth: 1
    implicitHeight: 68
    buttonRadius: Appearance.rounding.normal
    toggled: active || alert || iridescent
    colBackground: Appearance.colors.colLayer1
    colBackgroundToggled: alert ? Appearance.colors.colError : Appearance.colors.colPrimary
    colBackgroundToggledHover: alert ? Appearance.colors.colError : Appearance.colors.colPrimaryHover
    onClicked: {
        if (tile.triggerAction)
            tile.triggerAction();
    }

    IridescentFill { // Inside the background, so it shares its rounded mask
        parent: tile.background
        radius: tile.buttonRadius
        active: tile.iridescent
    }

    contentItem: Item {
        Column {
            anchors.centerIn: parent
            width: parent.width
            spacing: 3
            MaterialSymbol {
                anchors.horizontalCenter: parent.horizontalCenter
                text: tile.iconName
                iconSize: 24
                fill: tile.toggled ? 1 : 0
                color: tile.ink
            }
            StyledText {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                text: tile.label
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: tile.ink
            }
        }
    }

    StyledToolTip {
        text: tile.tooltip
    }
}
