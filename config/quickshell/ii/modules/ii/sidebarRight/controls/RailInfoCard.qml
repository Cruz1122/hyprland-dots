pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import Quickshell

// Label / value sheet for a rail page (connection details). Clicking a row
// copies its value.
Rectangle {
    id: root
    // [{ label, value }]
    property var entries: []
    property string emptyText: ""
    property int copiedIndex: -1

    implicitHeight: Math.max(48, rows.implicitHeight + 12)
    radius: Appearance.rounding.normal
    color: Appearance.colors.colLayer1

    Timer {
        id: copiedTimer
        interval: 1200
        onTriggered: root.copiedIndex = -1
    }

    StyledText {
        anchors.centerIn: parent
        visible: root.entries.length === 0
        text: root.emptyText
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: Appearance.colors.colSubtext
    }

    Column {
        id: rows
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            margins: 6
        }

        Repeater {
            model: root.entries
            Rectangle {
                id: entry
                required property int index
                required property var modelData
                width: rows.width
                height: 32
                radius: Appearance.rounding.verysmall
                color: entryArea.containsMouse ? Appearance.colors.colLayer2 : "transparent"

                MouseArea {
                    id: entryArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        Quickshell.clipboardText = entry.modelData.value;
                        root.copiedIndex = entry.index;
                        copiedTimer.restart();
                    }
                }
                StyledText {
                    id: labelText
                    anchors {
                        left: parent.left
                        leftMargin: 8
                        verticalCenter: parent.verticalCenter
                    }
                    text: entry.modelData.label
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
                StyledText {
                    anchors {
                        left: labelText.right
                        leftMargin: 12
                        right: parent.right
                        rightMargin: 8
                        verticalCenter: parent.verticalCenter
                    }
                    horizontalAlignment: Text.AlignRight
                    elide: Text.ElideMiddle
                    textFormat: Text.PlainText
                    text: root.copiedIndex === entry.index ? Translation.tr("Copied") : entry.modelData.value
                    font.family: Appearance.font.family.numbers
                    font.pixelSize: Appearance.font.pixelSize.smallie
                    color: root.copiedIndex === entry.index ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer1
                }
            }
        }
    }
}
