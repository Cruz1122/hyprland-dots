import QtQuick
import qs.modules.settings.components

SettingsButton {
    id: root
    property url url

    onClicked: {
        if (root.url.toString().length > 0) {
            Qt.openUrlExternally(root.url);
        }
    }
}
