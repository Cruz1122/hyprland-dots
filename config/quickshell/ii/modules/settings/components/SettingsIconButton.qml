import QtQuick
import qs.modules.settings.components

SettingsButton {
    id: root

    property string iconName: ""
    materialIcon: root.iconName
    label: ""
    width: SettingsMetrics.iconButtonSize
    height: SettingsMetrics.iconButtonSize
}
