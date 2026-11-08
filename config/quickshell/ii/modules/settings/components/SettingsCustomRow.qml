import QtQuick
import QtQuick.Layouts

// Hosts page.customDelegates[key] below the label. The delegate gets `row`
// (this row, for commit/value) and `entry` assigned when they exist as
// properties on its root item. A delegate whose root declares
// `inlineControl: true` (a single drop-down, say) sits beside the label like
// the built-in rows instead.
SettingsRow {
    id: row

    readonly property Component delegate: row.page?.customDelegates?.[row.settingKey] ?? null
    readonly property bool inlineControl: loader.item?.inlineControl === true

    stacked: !row.inlineControl
    controlFillsWidth: !row.inlineControl
    interactHandler: () => false

    Loader {
        id: loader
        Layout.fillWidth: !row.inlineControl
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
