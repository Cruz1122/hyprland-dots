import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.services

// Single-line text. Commits on Enter or focus loss; Esc restores the stored
// value. A rejected value keeps the field marked invalid until edited.
SettingsRow {
    id: row

    readonly property string stored: row.value === undefined || row.value === null ? "" : String(row.value)
    property string placeholder: row.entry?.placeholder ? Translation.tr(row.entry.placeholder) : ""
    property alias field: control

    controlPreferredWidth: 280
    controlFillsWidth: true
    focusVisible: false
    activateHandler: () => control.forceActiveFocus()
    interactHandler: () => false

    function commitField() {
        if (control.text === row.stored) {
            control.invalid = false;
            return;
        }
        control.invalid = !row.commit(control.text);
    }

    onRejected: control.invalid = true

    SettingsTextField {
        id: control
        Layout.fillWidth: true
        placeholderText: row.placeholder
        Accessible.name: row.label
        onEditingFinished: row.commitField()
        onTextEdited: control.invalid = false
        Keys.onEscapePressed: {
            control.text = row.stored;
            control.invalid = false;
            control.focus = false;
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
