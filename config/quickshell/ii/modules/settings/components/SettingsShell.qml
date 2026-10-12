import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs.modules.settings.components

Item {
    id: root

    property var pages: []
    property int currentPage: 0
    property real contentPadding: 8
    property bool showTitlebar: Config.options?.windows.showTitlebar
    property bool centerTitle: Config.options?.windows.centerTitle
    signal closeRequested()

    focus: true

    Keys.onPressed: (event) => {
        if (event.modifiers !== Qt.ControlModifier) return

        if (event.key === Qt.Key_PageDown) {
            root.currentPage = Math.min(root.currentPage + 1, root.pages.length - 1)
            event.accepted = true
        } else if (event.key === Qt.Key_PageUp) {
            root.currentPage = Math.max(root.currentPage - 1, 0)
            event.accepted = true
        } else if (event.key === Qt.Key_Tab) {
            root.currentPage = (root.currentPage + 1) % root.pages.length
            event.accepted = true
        } else if (event.key === Qt.Key_Backtab) {
            root.currentPage = (root.currentPage - 1 + root.pages.length) % root.pages.length
            event.accepted = true
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: root.contentPadding
        spacing: root.contentPadding

        Item {
            visible: root.showTitlebar
            Layout.fillWidth: true
            implicitHeight: Math.max(titleText.implicitHeight, closeButton.height)

            StyledText {
                id: titleText
                anchors {
                    left: root.centerTitle ? undefined : parent.left
                    horizontalCenter: root.centerTitle ? parent.horizontalCenter : undefined
                    verticalCenter: parent.verticalCenter
                    leftMargin: 12
                }
                text: Translation.tr("Settings")
                color: Appearance.colors.colOnLayer0
                font.family: Appearance.font.family.title
                font.pixelSize: Appearance.font.pixelSize.title
                font.variableAxes: Appearance.font.variableAxes.title
            }

            SettingsIconButton {
                id: closeButton
                anchors {
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                }
                iconName: "close"
                Accessible.name: Translation.tr("Close settings")
                onClicked: root.closeRequested()
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: root.contentPadding

            SettingsNavigation {
                id: navigation
                pages: root.pages
                currentIndex: root.currentPage
                expanded: root.width > 900
                configFilePath: `${Directories.config}/illogical-impulse/config.json`
                onPageSelected: root.currentPage = index
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: Appearance.m3colors.m3surfaceContainerLow
                radius: Appearance.rounding.windowRounding - root.contentPadding
                clip: true

                SettingsPageHost {
                    anchors.fill: parent
                    pages: root.pages
                    currentIndex: root.currentPage
                }
            }
        }
    }
}
