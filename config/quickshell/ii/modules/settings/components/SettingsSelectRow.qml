import QtQuick
import QtQuick.Layouts
import qs.modules.common.widgets
import qs.modules.settings.components

SettingsResponsiveRow {
    id: root

    property alias model: selectControl.model
    property alias currentIndex: selectControl.currentIndex
    property alias currentValue: selectControl.currentValue
    property alias textRole: selectControl.textRole
    property alias buttonIcon: selectControl.buttonIcon
    signal activated(int index)

    StyledComboBox {
        id: selectControl
        Layout.alignment: Qt.AlignRight
        Accessible.name: root.title
        onActivated: root.activated(index)
    }
}
