import QtQuick
import qs.modules.settings.components

SettingsButton {
    id: root
    property bool selected: false
    toggled: root.selected
}
