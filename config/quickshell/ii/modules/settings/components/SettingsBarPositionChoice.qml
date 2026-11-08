import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.settings.core

// Bar edge, stored as two flags: `bar.bottom` (bottom or right) and
// `bar.vertical` (left or right).
RowLayout {
    id: root

    property var row: null
    readonly property bool atBottom: (SettingsStore.revision, SettingsStore.value("bar.bottom") === true)
    readonly property bool isVertical: (SettingsStore.revision, SettingsStore.value("bar.vertical") === true)

    SettingsChoiceButtons {
        enabled: root.row?.rowEnabled ?? true
        accessibleName: root.row?.label ?? ""
        currentValue: (root.atBottom ? 1 : 0) + (root.isVertical ? 2 : 0)
        options: [
            { value: 0, label: Translation.tr("Top"), icon: "vertical_align_top" },
            { value: 1, label: Translation.tr("Bottom"), icon: "vertical_align_bottom" },
            { value: 2, label: Translation.tr("Left"), icon: "align_horizontal_left" },
            { value: 3, label: Translation.tr("Right"), icon: "align_horizontal_right" }
        ]
        onChosen: value => {
            SettingsStore.write("bar.bottom", (value & 1) !== 0);
            SettingsStore.write("bar.vertical", (value & 2) !== 0);
        }
    }

    Item {
        Layout.fillWidth: true
    }
}
