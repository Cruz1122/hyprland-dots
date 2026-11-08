import QtQuick
import QtQuick.Controls
import qs.modules.common

// Single-line themed text field (no line breaks). `invalid` paints the error
// outline.
TextField {
    id: root

    property bool invalid: false

    implicitHeight: SettingsMetrics.controlHeight + 4
    leftPadding: 14
    rightPadding: 14
    verticalAlignment: TextInput.AlignVCenter
    color: Appearance.colors.colOnLayer2
    placeholderTextColor: Appearance.colors.colSubtext
    selectedTextColor: Appearance.m3colors.m3onSecondaryContainer
    selectionColor: Appearance.colors.colSecondaryContainer
    selectByMouse: true
    // Show the start of long values (URLs, paths) while not editing.
    onTextChanged: if (!root.activeFocus) root.cursorPosition = 0
    onActiveFocusChanged: if (!root.activeFocus) root.cursorPosition = 0
    renderType: Text.NativeRendering
    font {
        family: Appearance.font.family.main
        pixelSize: Appearance.font.pixelSize.small
        variableAxes: Appearance.font.variableAxes.main
    }

    background: Rectangle {
        radius: SettingsMetrics.controlRadius
        color: root.enabled ? Appearance.colors.colLayer2 : Appearance.colors.colLayer2Disabled
        border.width: root.activeFocus || root.invalid ? 2 : 1
        border.color: root.invalid ? Appearance.colors.colError
            : root.activeFocus ? Appearance.colors.colPrimary
            : Appearance.colors.colOutlineVariant

        Behavior on border.color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }
    }
}
