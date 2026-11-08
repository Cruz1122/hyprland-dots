import QtQuick
import qs.modules.settings.core
import "../core/SettingsLogic.js" as Logic

// Device or application picker: a select row over the backend's choices
// (SettingsStore.choices, mapped by Logic.deviceChoices).
SettingsSelectRow {
    id: row
    rawOptions: (SettingsStore.revision, Logic.deviceChoices(SettingsStore.choices(row.settingKey)))
}
