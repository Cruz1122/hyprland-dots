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
        icon: o.icon ?? ""
    }))
    readonly property int currentIndex: row.options.findIndex(o => Logic.deepEqual(o.value, row.value))

    focusVisible: control.visualFocus
    activateHandler: () => control.popup.open()
    interactHandler: () => {
        if (row.options.length < 2)
            return false;
        const next = (Math.max(0, row.currentIndex) + 1) % row.options.length;
        control.currentIndex = next;
        return row.commit(row.options[next].value);
    }

    onRejected: control.currentIndex = row.currentIndex

    TextMetrics {
        id: widest
        font.family: Appearance.font.family.main
        font.pixelSize: Appearance.font.pixelSize.small
        text: row.options.reduce((a, o) => o.label.length > a.length ? o.label : a, "")
    }

    StyledComboBox {
        id: control
        Layout.fillWidth: row.compact
        Layout.preferredWidth: Math.min(360, Math.max(240, widest.width + 80))
        Layout.maximumWidth: 360
        model: row.options
        textRole: "label"
        Accessible.name: row.label
        onActivated: index => row.commit(row.options[index].value)
    }

    Binding {
        target: control
        property: "currentIndex"
        value: row.currentIndex
        restoreMode: Binding.RestoreNone
    }
}
