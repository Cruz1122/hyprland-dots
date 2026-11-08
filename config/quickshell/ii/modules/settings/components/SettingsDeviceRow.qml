import QtQuick
import qs.modules.settings.core

// Device or application picker: a select row over the backend's choices
// (SettingsStore.choices). Choice labels are names, not English source
// strings, so they are not translated; choice icons are application icon
// names, not Material Symbols, so they are dropped.
SettingsSelectRow {
    id: row
    rawOptions: (SettingsStore.revision, SettingsStore.choices(row.settingKey)).map(o => Object.assign({}, o, { translate: false, icon: "" }))
}
