import QtQuick
import qs.modules.common
import qs.modules.settings.components

Rectangle {
    id: root

    property alias source: preview.source
    property real previewAspectRatio: 16 / 9
    property bool preserveAspectCrop: true
    default property alias overlayData: overlay.data

    height: width / Math.max(0.001, root.previewAspectRatio)
    radius: SettingsMetrics.cardRadius
    color: Appearance.colors.colLayer2
    clip: true

    Image {
        id: preview
        anchors.fill: parent
        fillMode: root.preserveAspectCrop ? Image.PreserveAspectCrop : Image.PreserveAspectFit
        cache: false
    }

    Item {
        id: overlay
        anchors.fill: parent
    }
}
