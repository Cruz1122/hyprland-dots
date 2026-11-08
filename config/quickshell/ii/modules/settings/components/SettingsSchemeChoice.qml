import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import "../core/SettingsLogic.js" as Logic

// Color scheme drop-down that regenerates the palette after a change, as
// the scheme is only read when colors are generated (switchwall.sh).
RowLayout {
    id: root

    readonly property bool inlineControl: true
    property var row: null
    readonly property var options: (root.row?.entry?.options ?? []).map(o => ({
        value: o.value,
        label: Translation.tr(String(o.label ?? o.value))
    }))
    readonly property int currentIndex: root.options.findIndex(o => Logic.deepEqual(o.value, root.row?.value))

    StyledComboBox {
        id: combo
        Layout.preferredWidth: SettingsMetrics.selectWidth
        enabled: root.row?.rowEnabled ?? false
        model: root.options
        textRole: "label"
        Accessible.name: root.row?.label ?? ""
        // ComboBox resets currentIndex when its model is replaced (the row
        // arrives after creation); reapply.
        onModelChanged: Qt.callLater(() => combo.currentIndex = root.currentIndex)
        onActivated: index => {
            if (root.row?.commit(root.options[index].value))
                regenerate.restart();
            else
                combo.currentIndex = root.currentIndex;
        }
    }

    Binding {
        target: combo
        property: "currentIndex"
        value: root.currentIndex
        restoreMode: Binding.RestoreNone
    }

    // switchwall.sh reads the scheme from config.json, which is written
    // after Config.readWriteDelay; wait for it, and coalesce quick changes.
    Timer {
        id: regenerate
        interval: 600
        onTriggered: Quickshell.execDetached([Directories.wallpaperSwitchScriptPath, "--noswitch"])
    }
}
