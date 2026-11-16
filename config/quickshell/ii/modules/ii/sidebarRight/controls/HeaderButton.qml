import qs.modules.common
import qs.modules.common.widgets
import QtQuick

// Quiet round icon button: no resting background.
RippleButton {
    id: headerButton
    required property string buttonIcon
    property string tooltip: ""
    implicitWidth: 36
    implicitHeight: 36
    buttonRadius: height / 2
    contentItem: MaterialSymbol {
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        text: headerButton.buttonIcon
        iconSize: 20
        color: headerButton.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colSubtext
    }
    StyledToolTip {
        text: headerButton.tooltip
    }
}
