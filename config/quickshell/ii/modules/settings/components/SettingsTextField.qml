import QtQuick
import QtQuick.Controls
import qs.modules.common
import qs.modules.settings.components

TextField {
    id: root

    property string label: ""
    height: SettingsMetrics.controlHeight
    leftPadding: 12
    rightPadding: 12
    color: Appearance.colors.colOnLayer2
    placeholderTextColor: Appearance.colors.colSubtext
    font.family: Appearance.font.family.main
    Accessible.name: root.label

    background: Rectangle {
        radius: SettingsMetrics.controlRadius
        color: Appearance.colors.colLayer2
        border.width: root.activeFocus ? 2 : 1
        border.color: root.activeFocus ? Appearance.colors.colPrimary : Appearance.m3colors.m3outlineVariant
    }
}
