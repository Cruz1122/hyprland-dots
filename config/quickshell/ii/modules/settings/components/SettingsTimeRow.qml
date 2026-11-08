import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

// "HH:MM" time with hour and minute spin boxes.
SettingsRow {
    id: row

    readonly property var parts: {
        const match = /^(\d{1,2}):(\d{2})$/.exec(String(row.value ?? ""));
        return match ? [parseInt(match[1]), parseInt(match[2])] : [0, 0];
    }

    focusVisible: hours.activeFocus || minutes.activeFocus
    interactHandler: () => false

    function pad(n) {
        return String(n).padStart(2, "0");
    }

    function commitParts() {
        row.commit(`${row.pad(hours.value)}:${row.pad(minutes.value)}`);
    }

    onRejected: {
        hours.value = row.parts[0];
        minutes.value = row.parts[1];
    }

    StyledSpinBox {
        id: hours
        from: 0
        to: 23
        Accessible.name: row.label
        onValueModified: row.commitParts()
    }

    StyledText {
        text: ":"
        color: Appearance.colors.colOnLayer1
    }

    StyledSpinBox {
        id: minutes
        from: 0
        to: 59
        stepSize: row.entry?.step ?? 1
        Accessible.name: row.label
        onValueModified: row.commitParts()
    }

    Binding {
        target: hours
        property: "value"
        value: row.parts[0]
        restoreMode: Binding.RestoreNone
    }

    Binding {
        target: minutes
        property: "value"
        value: row.parts[1]
        restoreMode: Binding.RestoreNone
    }
}
