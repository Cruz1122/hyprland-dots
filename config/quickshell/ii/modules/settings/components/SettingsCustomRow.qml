import QtQuick
import QtQuick.Layouts

// Hosts page.customDelegates[key] below the label. The delegate gets `row`
// (this row, for commit/value) and `entry` assigned when they exist as
// properties on its root item.
SettingsRow {
    id: row

    readonly property Component delegate: row.page?.customDelegates?.[row.settingKey] ?? null

    stacked: true
    controlFillsWidth: true
    interactHandler: () => false

    Loader {
        Layout.fillWidth: true
        active: row.delegate !== null
        sourceComponent: row.delegate
        onLoaded: {
            if ("row" in item)
                item.row = row;
            if ("entry" in item)
                item.entry = row.entry;
        }
    }
}
