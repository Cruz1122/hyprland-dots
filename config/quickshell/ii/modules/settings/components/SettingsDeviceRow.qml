import QtQuick
import qs.services
import qs.modules.settings.core
import "../core/SettingsLogic.js" as Logic

// Device or application picker: a select row over the backend's choices
// (SettingsStore.choices, mapped by Logic.deviceChoices).
SettingsSelectRow {
    id: row
    rawOptions: (SettingsStore.revision, Logic.deviceChoices(SettingsStore.choices(row.settingKey)))

    // Backend choices carry no descriptions; when the registry entry lists
    // options with one (power.profile), the selected value's shows as "Now: …".
    readonly property var describedOption: (row.entry?.options ?? []).find(o => o.description && Logic.deepEqual(o.value, row.value)) ?? null
    optionNote: row.describedOption ? Translation.tr("Now: %1").arg(Translation.tr(row.describedOption.description)) : ""
}
