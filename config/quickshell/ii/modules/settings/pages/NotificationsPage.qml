import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.settings.components
import qs.services

SettingsPage {
    id: root
    pageId: "notifications"

    customDelegates: ({
        "notifications.monitor.name": monitorPicker
    })

    // Monitor names come from the connected screens; a configured monitor
    // that is unplugged stays listed so the stored value is still visible.
    Component {
        id: monitorPicker

        RowLayout {
            id: picker
            readonly property bool inlineControl: true
            property var row: null
            readonly property string stored: picker.row?.value ?? ""
            readonly property var names: {
                // A screen without a name cannot be chosen: "" means none.
                const list = Quickshell.screens.map(s => s.name).filter(n => n.length > 0);
                if (picker.stored && !list.includes(picker.stored))
                    list.unshift(picker.stored);
                return list;
            }

            StyledComboBox {
                id: combo
                Layout.preferredWidth: SettingsMetrics.selectWidth
                enabled: picker.row?.rowEnabled ?? false
                model: picker.names
                // No monitor stored yet: say so rather than show an empty box.
                displayText: combo.currentIndex >= 0 ? combo.currentText : Translation.tr("Choose a monitor")
                Accessible.name: picker.row?.label ?? ""
                // ComboBox resets currentIndex when its model is replaced
                // (languages and screens arrive asynchronously); reapply.
                onModelChanged: Qt.callLater(() => combo.currentIndex = picker.names.indexOf(picker.stored))
                onActivated: index => {
                    if (!picker.row.commit(picker.names[index]))
                        combo.currentIndex = picker.names.indexOf(picker.stored);
                }
            }

            Binding {
                target: combo
                property: "currentIndex"
                value: picker.names.indexOf(picker.stored)
                restoreMode: Binding.RestoreNone
            }
        }
    }
}
