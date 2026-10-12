import QtQuick
import qs.modules.settings.components

SettingsButton {
    id: root
    property var callback

    onClicked: {
        if (root.callback) {
            root.callback();
        }
    }
}
