import QtQuick
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.panels.lock

// Lock screen power action. With requirePassword the click only arms the
// action and the send button confirms it with the password; without it the
// action runs at once. With no targetAction it is a plain button (onClicked).
RippleButton {
    id: root
    required property LockContext context
    required property string symbol
    property bool requirePassword: false
    property var targetAction: null
    readonly property bool armed: targetAction !== null && context.targetAction === targetAction

    implicitWidth: 44
    implicitHeight: 44
    buttonRadius: height / 2
    toggled: armed
    onClicked: {
        if (targetAction === null)
            return;
        if (!requirePassword) {
            context.unlocked(targetAction);
            return;
        }
        if (armed) {
            context.resetTargetAction();
        } else {
            context.targetAction = targetAction;
            context.shouldReFocus();
        }
    }
    contentItem: MaterialSymbol {
        anchors.centerIn: parent
        horizontalAlignment: Text.AlignHCenter
        text: root.symbol
        iconSize: Appearance.font.pixelSize.huge
        color: root.armed ? Appearance.colors.colOnPrimary : Appearance.colors.colSubtext
    }
}
