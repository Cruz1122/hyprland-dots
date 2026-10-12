import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.common
import qs.modules.common.functions
import qs.modules.settings.components

ColumnLayout {
    id: root

    property var pages: []
    property int currentIndex: 0
    property bool expanded: true
    property string configFilePath: ""
    property bool configPathCopied: false
    signal pageSelected(int index)

    Layout.fillHeight: true
    Layout.minimumWidth: Layout.preferredWidth
    Layout.maximumWidth: Layout.preferredWidth
    Layout.preferredWidth: root.expanded ? 168 : 52
    spacing: 8

    Behavior on Layout.preferredWidth {
        NumberAnimation {
            duration: SettingsMetrics.transitionDuration
            easing.type: Easing.OutCubic
        }
    }

    SettingsToggleButton {
        Layout.fillWidth: true
        label: root.expanded ? "Collapse" : ""
        materialIcon: root.expanded ? "left_panel_close" : "left_panel_open"
        checked: root.expanded
        Accessible.name: root.expanded ? "Collapse navigation" : "Expand navigation"
        onClicked: root.expanded = !root.expanded
    }

    SettingsActionButton {
        id: configButton
        label: root.expanded ? (root.configPathCopied ? "Path copied" : "Config file") : ""
        materialIcon: root.configPathCopied ? "check" : "edit"
        altAction: function() {
            Quickshell.clipboardText = FileUtils.trimFileProtocol(root.configFilePath)
            root.configPathCopied = true
            copyResetTimer.restart()
        }
        onClicked: Qt.openUrlExternally(root.configFilePath)

        SettingsTooltip {
            text: "Open the shell config file\nAlternatively right-click to copy path"
        }

        Timer {
            id: copyResetTimer
            interval: 1500
            onTriggered: root.configPathCopied = false
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 4

        Repeater {
            model: root.pages

            delegate: SettingsNavigationItem {
                required property var modelData
                required property int index
                page: modelData
                pageIndex: index
                expanded: root.expanded
                selected: root.currentIndex === index
                onPageSelected: root.pageSelected(index)
            }
        }
    }

    Item {
        Layout.fillHeight: true
    }
}
