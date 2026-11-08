import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs.modules.settings.core

// Window content: optional titlebar, navigation, page host, confirmation bar
// and error toast. settings.qml owns the page index; this item reports
// navigation through pageRequested().
Item {
    id: root

    property string currentPageId: ""
    property bool showTitlebar: true
    property bool centerTitle: true
    readonly property alias host: pageHost
    readonly property alias navigation: navigation

    signal pageRequested(string pageId)
    signal revealRequested(string key)
    signal closeRequested()

    function focusSearch() {
        navigation.focusSearch();
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 8
        spacing: 4

        Item {
            visible: root.showTitlebar
            Layout.fillWidth: true
            implicitHeight: 40

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                anchors.horizontalCenter: root.centerTitle ? parent.horizontalCenter : undefined
                anchors.left: root.centerTitle ? undefined : parent.left
                anchors.leftMargin: 12
                text: Translation.tr("Settings")
                font.family: Appearance.font.family.title
                font.variableAxes: Appearance.font.variableAxes.title
                font.pixelSize: Appearance.font.pixelSize.title
                color: Appearance.colors.colOnLayer0
            }

            SettingsIconButton {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                iconName: "close"
                tooltip: Translation.tr("Close settings")
                onClicked: root.closeRequested()
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 8

            SettingsNavigation {
                id: navigation
                windowWidth: root.width
                currentPageId: root.currentPageId
                onPageSelected: pageId => root.pageRequested(pageId)
                onResultActivated: result => {
                    if (result.kind === "entry")
                        root.revealRequested(result.key);
                    else if (result.kind === "section") {
                        root.pageRequested(result.pageId);
                        pageHost.currentItem?.scrollToSection?.(result.sectionId);
                    } else
                        root.pageRequested(result.pageId);
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                SettingsPageHost {
                    id: pageHost
                    anchors.fill: parent
                }

                SettingsErrorToast {
                    width: Math.min(implicitWidth, parent.width - 32) // size-ok: floating toast, not in a layout
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: confirmBar.visible ? confirmBar.top : parent.bottom
                    anchors.bottomMargin: 16
                }

                SettingsConfirmBar {
                    id: confirmBar
                    width: Math.min(implicitWidth, parent.width - 32) // size-ok: floating bar, not in a layout
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 16
                }
            }
        }
    }
}
