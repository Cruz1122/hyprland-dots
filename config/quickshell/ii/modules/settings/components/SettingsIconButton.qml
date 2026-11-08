import QtQuick
import qs.modules.common
import qs.modules.common.widgets

// Round icon-only button. `tooltip` doubles as the accessible name and only
// shows while hovered.
RippleButton {
    id: root

    property string iconName: ""
    property string tooltip: ""
    property real iconSize: 20
    property real iconRotation: 0
    property color iconColor: Appearance.colors.colOnSurfaceVariant
    property real size: 36

    implicitWidth: root.size
    implicitHeight: root.size
    buttonRadius: root.size / 2
    colBackgroundHover: Appearance.colors.colLayer2Hover
    colRipple: Appearance.colors.colLayer2Active
    Accessible.name: root.tooltip
    Accessible.role: Accessible.Button

    contentItem: MaterialSymbol {
        text: root.iconName
        iconSize: root.iconSize
        rotation: root.iconRotation
        color: root.iconColor
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }

    StyledToolTip {
        text: root.tooltip
        extraVisibleCondition: root.tooltip.length > 0
    }

    SettingsFocusRing {
        shown: root.visualFocus
        ringRadius: root.size / 2
    }
}
