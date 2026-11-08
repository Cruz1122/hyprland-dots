import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs.modules.settings.core
import "../core/SettingsLogic.js" as Logic

// Drop-down for enum entries. SettingsDeviceRow reuses it with backend
// choices.
SettingsRow {
    id: row

    property var rawOptions: row.entry?.options ?? []
    readonly property var options: row.rawOptions.map(o => ({
        value: o.value,
        label: o.translate === false ? String(o.label ?? o.value) : Translation.tr(String(o.label ?? o.value)),
        icon: o.icon ?? "",
        description: o.description ? Translation.tr(o.description) : ""
    }))
    readonly property int currentIndex: row.options.findIndex(o => Logic.deepEqual(o.value, row.value))

    focusVisible: control.visualFocus
    needsValue: true
    optionNote: row.currentIndex >= 0 && row.options[row.currentIndex].description ? Translation.tr("Now: %1").arg(row.options[row.currentIndex].description) : ""
    activateHandler: () => control.popup.open()
    interactHandler: () => {
        if (row.options.length < 2)
            return false;
        const next = (Math.max(0, row.currentIndex) + 1) % row.options.length;
        control.currentIndex = next;
        return row.commit(row.options[next].value);
    }

    onRejected: control.currentIndex = row.currentIndex

    StyledComboBox {
        id: control
        Layout.fillWidth: row.compact
        Layout.preferredWidth: SettingsMetrics.selectWidth
        model: row.options
        textRole: "label"
        Accessible.name: row.label
        onActivated: index => row.commit(row.options[index].value)
        // A new model (device rows rebuild their options on every store
        // revision; labels change when the translations load) resets the
        // combo to its first item while row.currentIndex keeps its value,
        // so the Binding below would not write it again.
        onModelChanged: control.currentIndex = row.currentIndex
        onCountChanged: control.currentIndex = row.currentIndex
    }

    Binding {
        target: control
        property: "currentIndex"
        value: row.currentIndex
        restoreMode: Binding.RestoreNone
    }
}
