import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

// Numeric slider. `uiScale` multiplies the stored value for display
// (0.5 shown as 50 with unit "%"). Writes once on release, or on each
// keyboard step.
SettingsRow {
    id: row

    readonly property real uiScale: row.entry?.uiScale ?? 1
    readonly property int decimals: row.entry?.decimals ?? (row.entry?.type === "int" ? 0 : (row.uiScale >= 100 ? 0 : 2))
    readonly property string unit: row.entry?.unit ?? ""
    readonly property real stored: typeof row.value === "number" ? row.value : (row.entry?.min ?? 0)

    controlPreferredWidth: 300
    controlFillsWidth: true
    focusVisible: control.visualFocus
    interactHandler: () => false

    function format(displayed) {
        return `${Number(displayed).toFixed(row.decimals)}${row.unit}`;
    }

    function commitControl() {
        row.commit(control.value / row.uiScale);
    }

    onRejected: control.value = row.stored * row.uiScale

    StyledSlider {
        id: control
        Layout.fillWidth: true
        Layout.minimumWidth: 120
        from: (row.entry?.min ?? 0) * row.uiScale
        to: (row.entry?.max ?? 1) * row.uiScale
        stepSize: (row.entry?.step ?? 0) * row.uiScale
        snapMode: stepSize > 0 ? Slider.SnapAlways : Slider.NoSnap
        stopIndicatorValues: []
        usePercentTooltip: false
        tooltipContent: row.format(control.value)
        Accessible.name: row.label
        onPressedChanged: {
            if (!control.pressed)
                row.commitControl();
        }
        onMoved: {
            if (!control.pressed)
                row.commitControl();
        }
    }

    StyledText {
        Layout.preferredWidth: valueMetrics.width + 4
        horizontalAlignment: Text.AlignRight
        text: row.format(control.value)
        color: Appearance.colors.colOnLayer1
        font.family: Appearance.font.family.numbers
        font.variableAxes: Appearance.font.variableAxes.numbers
    }

    TextMetrics {
        id: valueMetrics
        font.family: Appearance.font.family.numbers
        font.pixelSize: Appearance.font.pixelSize.small
        text: row.format(-Math.max(Math.abs(control.from), Math.abs(control.to)))
    }

    Binding {
        target: control
        property: "value"
        value: row.stored * row.uiScale
        when: !control.pressed
        restoreMode: Binding.RestoreNone
    }
}
