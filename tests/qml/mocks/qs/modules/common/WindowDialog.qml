import QtQuick
import QtQuick.Layouts

Rectangle {
    id: root
    property bool show: false
    property real backgroundWidth: 420
    property real currentHeight: content.implicitHeight + 48
    // Mirrors the real WindowDialog default binding. Callers that do not pin
    // backgroundHeight inherit the real close/reopen-to-zero behavior.
    property real backgroundHeight: currentHeight
    default property alias contentData: content.data
    signal dismiss()
    onShowChanged: root.currentHeight = root.show ? root.backgroundHeight : 0
    onBackgroundHeightChanged: if (root.show) root.currentHeight = root.backgroundHeight
    color: "#cc000000"
    // The real WindowDialog's own visibility derives from its animated content
    // height; callers must explicitly hide the full-screen mouse area as well.
    visible: root.currentHeight > 0
    implicitHeight: root.currentHeight

    ColumnLayout {
        id: content
        anchors.centerIn: parent
        width: Math.min(parent.width - 32, root.backgroundWidth)
        spacing: 16
    }
}
