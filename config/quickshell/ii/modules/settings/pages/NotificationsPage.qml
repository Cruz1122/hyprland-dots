import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.settings.components

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
            property var row: null
            readonly property string stored: picker.row?.value ?? ""
            readonly property var names: {
                const list = Quickshell.screens.map(s => s.name);
                if (picker.stored && !list.includes(picker.stored))
                    list.unshift(picker.stored);
                return list;
            }

            StyledComboBox {
                id: combo
                Layout.preferredWidth: 280
                Layout.maximumWidth: 360
                enabled: picker.row?.rowEnabled ?? false
                model: picker.names
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

            Item {
                Layout.fillWidth: true
            }
        }
    }
}
