import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

// Read-only value: page.infoValues[key] when the page provides it, otherwise
// the store value.
SettingsRow {
    id: row

    readonly property var shown: row.page?.infoValues?.[row.settingKey] ?? row.value

    interactHandler: () => false

    StyledText {
        Layout.maximumWidth: 360
        text: row.shown === undefined || row.shown === null ? "—" : String(row.shown)
        elide: Text.ElideMiddle
        color: Appearance.colors.colOnLayer1
        textFormat: Text.PlainText
    }
}
