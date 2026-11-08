import QtQuick
import qs.modules.common
import qs.modules.common.widgets
import qs.services

// Integer spin box (use a slider for real values). Typed text commits on
// Enter or focus loss. `uiScale` converts the stored value for display
// (1500 seconds with 1/60 shows 25 minutes); min, max and step stay in
// stored units, and the displayed value is divided back and rounded.
SettingsRow {
    id: row

    readonly property real uiScale: row.entry?.uiScale ?? 1
    readonly property int stored: Math.round((typeof row.value === "number" ? row.value : (row.entry?.min ?? 0)) * row.uiScale)

    focusVisible: control.activeFocus
    needsValue: true
    interactHandler: () => false

    onRejected: control.value = row.stored

    StyledSpinBox {
        id: control
        from: row.entry?.min !== undefined ? Math.ceil(row.entry.min * row.uiScale) : -2147483647
        to: row.entry?.max !== undefined ? Math.floor(row.entry.max * row.uiScale) : 2147483647
        stepSize: Math.max(1, Math.round((row.entry?.step ?? 1) * row.uiScale))
        Accessible.name: row.label
        onValueModified: row.commit(Math.round(control.value / row.uiScale))
    }

    StyledText {
        visible: text.length > 0
        text: row.entry?.unit ? Translation.tr(row.entry.unit) : ""
        color: Appearance.colors.colSubtext
    }

    Binding {
        target: control
        property: "value"
        value: row.stored
        restoreMode: Binding.RestoreNone
    }
}
