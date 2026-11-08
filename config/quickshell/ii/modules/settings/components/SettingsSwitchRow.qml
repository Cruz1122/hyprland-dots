import QtQuick
import qs.modules.common.widgets

SettingsRow {
    id: row

    focusVisible: control.visualFocus
    activateHandler: () => row.flip()
    interactHandler: () => row.flip()

    function flip() {
        control.checked = !control.checked;
        row.commit(control.checked);
    }

    onRejected: control.checked = row.value === true

    StyledSwitch {
        id: control
        Accessible.name: row.label
        onToggled: row.commit(control.checked)
    }

    Binding {
        target: control
        property: "checked"
        value: row.value === true
        restoreMode: Binding.RestoreNone
    }
}
