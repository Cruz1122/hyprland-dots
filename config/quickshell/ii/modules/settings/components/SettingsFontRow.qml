import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

// Font family picker over the installed families; a stored family that is
// not installed stays listed so it can be seen and kept.
SettingsRow {
    id: row

    readonly property string stored: row.value === undefined || row.value === null ? "" : String(row.value)
    readonly property var families: {
        const list = Qt.fontFamilies();
        return row.stored.length > 0 && !list.includes(row.stored) ? [row.stored].concat(list) : list;
    }

    focusVisible: control.visualFocus
    activateHandler: () => control.popup.open()
    interactHandler: () => false

    onRejected: control.currentIndex = row.families.indexOf(row.stored)

    StyledComboBox {
        id: control
        Layout.fillWidth: row.compact
        Layout.preferredWidth: SettingsMetrics.selectWidth
        model: row.families
        Accessible.name: row.label
        onActivated: index => row.commit(row.families[index])
    }

    Binding {
        target: control
        property: "currentIndex"
        value: row.families.indexOf(row.stored)
        restoreMode: Binding.RestoreNone
    }
}
