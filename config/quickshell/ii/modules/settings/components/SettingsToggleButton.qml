import QtQuick
import qs.modules.settings.components

SettingsButton {
    id: root

    toggled: root.checked
    onClicked: root.checked = !root.checked
}
