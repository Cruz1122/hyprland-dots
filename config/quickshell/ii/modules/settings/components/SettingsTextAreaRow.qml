import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

// Multi-line text below the label. Commits when focus leaves the field.
SettingsRow {
    id: row

    readonly property string stored: row.value === undefined || row.value === null ? "" : String(row.value)
    property bool invalid: false

    stacked: true
    controlFillsWidth: true
    activateHandler: () => control.forceActiveFocus()
    interactHandler: () => false

    onRejected: row.invalid = true

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: Math.max(96, control.implicitHeight)
        radius: SettingsMetrics.controlRadius
        color: Appearance.colors.colLayer2
        border.width: control.activeFocus || row.invalid ? 2 : 1
        border.color: row.invalid ? Appearance.colors.colError : control.activeFocus ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant

        StyledTextArea {
            id: control
            anchors.fill: parent
            padding: 12
            wrapMode: TextEdit.Wrap
            background: null
            color: Appearance.colors.colOnLayer2
            Accessible.name: row.label
            onTextChanged: if (control.activeFocus) row.invalid = false
            onActiveFocusChanged: {
                if (!control.activeFocus && control.text !== row.stored)
                    row.invalid = !row.commit(control.text);
            }
        }
    }

    Binding {
        target: control
        property: "text"
        value: row.stored
        when: !control.activeFocus
        restoreMode: Binding.RestoreNone
    }
}
