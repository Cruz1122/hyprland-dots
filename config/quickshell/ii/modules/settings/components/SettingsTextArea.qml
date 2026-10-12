import QtQuick
import QtQuick.Controls
import qs.modules.common
import qs.modules.settings.components

TextArea {
    id: root

    property string label: ""
    height: 112
    padding: 12
    wrapMode: TextArea.Wrap
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
