import QtQuick
import QtQuick.Layouts
import qs.modules.settings.components

RowLayout {
    id: root

    property alias text: pathField.text
    property string label: ""
    property string buttonLabel: "Browse"
    signal browseRequested()
    Layout.fillWidth: true

    SettingsTextField {
        id: pathField
        label: root.label
        Layout.fillWidth: true
    }

    SettingsButton {
        label: root.buttonLabel
        materialIcon: "folder_open"
        onClicked: root.browseRequested()
    }
}
