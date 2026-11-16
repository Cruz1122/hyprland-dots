import qs.modules.common
import qs.modules.common.widgets
import QtQuick

// Ghost icon button for the dock's ends, styled like the side rails'
// HeaderButton. Its tooltip is a popup window: the dock window is too short
// to hold an in-window tooltip above the button.
RippleButton {
    id: root
    required property string buttonIcon
    property string tooltip: ""
    property real size: 36
    implicitWidth: size
    implicitHeight: size
    buttonRadius: height / 2
    contentItem: MaterialSymbol {
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        text: root.buttonIcon
        iconSize: Math.round(root.size * 0.56)
        color: root.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colSubtext
    }
    PopupToolTip {
        extraVisibleCondition: root.tooltip.length > 0
        text: root.tooltip
    }
}
