import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.settings.components

StyledFlickable {
    id: root

    property string title: ""
    property string description: ""
    property real baseWidth: 600
    property bool forceWidth: false
    property real contentMargin: SettingsMetrics.pageMargin
    property real maxContentWidth: SettingsMetrics.maxContentWidth
    default property alias contentData: contentColumn.data

    clip: true
    contentHeight: contentColumn.implicitHeight + SettingsMetrics.pageBottomPadding

    ColumnLayout {
        id: contentColumn
        width: root.forceWidth ? root.baseWidth : Math.min(root.maxContentWidth, Math.max(0, root.width - root.contentMargin * 2))
        anchors {
            top: parent.top
            horizontalCenter: parent.horizontalCenter
            topMargin: root.contentMargin
        }
        spacing: SettingsMetrics.sectionSpacing
    }
}
