import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.settings.components

GridLayout {
    id: root

    property string title: ""
    property string description: ""
    property string icon: ""
    property string text: ""
    property string buttonIcon: ""
    property bool uniform: false
    readonly property bool hasLabel: root.title.length > 0 || root.text.length > 0 || root.description.length > 0 || root.icon.length > 0 || root.buttonIcon.length > 0
    property bool compact: width < SettingsMetrics.compactBreakpoint
    default property alias controlData: controlSlot.data

    columns: root.compact || !root.hasLabel ? 1 : 2
    columnSpacing: SettingsMetrics.rowSpacing
    rowSpacing: root.compact ? SettingsMetrics.compactRowSpacing : SettingsMetrics.rowSpacing
    Layout.fillWidth: true

    ColumnLayout {
        id: labelColumn
        visible: root.hasLabel
        Layout.fillWidth: true
        Layout.minimumWidth: SettingsMetrics.minLabelWidth
        Layout.column: 0
        Layout.row: 0

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            MaterialSymbol {
                visible: (root.icon || root.buttonIcon).length > 0
                text: root.icon || root.buttonIcon
                iconSize: Appearance.font.pixelSize.large
            }

            StyledText {
                Layout.fillWidth: true
                text: root.title || root.text
                color: Appearance.colors.colOnLayer1
                wrapMode: Text.WordWrap
            }
        }

        StyledText {
            visible: root.description.length > 0
            Layout.fillWidth: true
            text: root.description
            color: Appearance.colors.colSubtext
            wrapMode: Text.WordWrap
            font.pixelSize: Appearance.font.pixelSize.smaller
        }
    }

    ColumnLayout {
        id: controlSlot
        Layout.fillWidth: true
        Layout.column: root.compact || !root.hasLabel ? 0 : 1
        Layout.row: root.compact ? 1 : 0
        Layout.columnSpan: root.hasLabel && !root.compact ? 1 : 1
    }
}
