import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.settings.components

SettingsResponsiveRow {
    id: root

    property alias checked: switchControl.checked
    signal toggled(bool checked)

    Switch {
        id: switchControl
        Layout.alignment: Qt.AlignRight
        Accessible.name: root.title
        onToggled: root.toggled(checked)
    }
}
