import QtQuick
import QtQuick.Layouts
import qs.modules.common.widgets
import qs.modules.settings.components

SettingsIconButton {
    id: root

    property string helpText: ""
    iconName: "info"
    Accessible.name: root.helpText

    SettingsTooltip {
        visible: root.helpText.length > 0
        text: root.helpText
    }
}
