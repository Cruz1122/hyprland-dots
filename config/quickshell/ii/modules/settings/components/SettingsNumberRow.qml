import QtQuick
import QtQuick.Layouts
import qs.modules.common.widgets
import qs.modules.settings.components

SettingsResponsiveRow {
    id: root

    property alias value: numberControl.value
    property alias from: numberControl.from
    property alias to: numberControl.to
    property alias stepSize: numberControl.stepSize

    StyledSpinBox {
        id: numberControl
        Layout.alignment: Qt.AlignRight
        Accessible.name: root.title
    }
}
