import qs.modules.common
import QtQuick

Canvas {
    id: root
    property real remaining: 1
    property color ringColor: Appearance.colors.colOnLayer1
    property color trackColor: Qt.rgba(ringColor.r, ringColor.g, ringColor.b, 0.18)
    implicitWidth: 28
    implicitHeight: 28
    onRemainingChanged: root.requestPaint()
    onRingColorChanged: root.requestPaint()
    onTrackColorChanged: root.requestPaint()
    onWidthChanged: root.requestPaint()
    onHeightChanged: root.requestPaint()
    onPaint: {
        const context = getContext("2d");
        context.clearRect(0, 0, width, height);
        const radius = Math.max(0, Math.min(width, height) / 2 - 3);
        context.lineWidth = 3;
        context.lineCap = "round";
        context.beginPath();
        context.strokeStyle = root.trackColor;
        context.arc(width / 2, height / 2, radius, 0, Math.PI * 2);
        context.stroke();
        context.beginPath();
        context.strokeStyle = root.ringColor;
        context.arc(width / 2, height / 2, radius, -Math.PI / 2,
            -Math.PI / 2 + Math.PI * 2 * Math.max(0, Math.min(1, root.remaining)));
        context.stroke();
    }
}
