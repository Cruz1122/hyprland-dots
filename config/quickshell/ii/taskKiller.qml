//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ApplicationWindow {
    id: root

    visible: true
    width: 520
    height: 420
    minimumWidth: 420
    minimumHeight: 280
    title: "Kill task"
    color: "#191919"

    onClosing: Qt.quit()

    function killProcess(pid) {
        if (pid > 0)
            Quickshell.execDetached(["kill", "-TERM", String(pid)]);
        root.close();
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 12

        RowLayout {
            Layout.fillWidth: true

            StyledText {
                text: "Kill task"
                font.pixelSize: Appearance.font.pixelSize.title
                Layout.fillWidth: true
            }

            RippleButton {
                implicitWidth: 36
                implicitHeight: 36
                onClicked: root.close()
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: "close"
                    iconSize: 20
                }
            }
        }

        StyledText {
            text: "Selecciona una aplicación abierta para terminar su proceso."
            color: Appearance.colors.colSubtext
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }

        ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            background: Rectangle {
                color: "#191919"
                radius: 8
            }

            ColumnLayout {
                width: root.width - 32
                spacing: 10

                Repeater {
                    model: HyprlandData.windowList

                    delegate: RippleButton {
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.leftMargin: 8
                        Layout.rightMargin: 8
                        Layout.topMargin: 3
                        Layout.bottomMargin: 3
                        implicitHeight: 48
                        colBackground: "#434343"
                        colBackgroundHover: "#505050"
                        onClicked: root.killProcess(modelData.pid)

                        contentItem: RowLayout {
                            spacing: 10

                            Image {
                                source: Quickshell.iconPath(AppSearch.guessIcon(modelData.class), "image-missing")
                                sourceSize.width: 24
                                sourceSize.height: 24
                                fillMode: Image.PreserveAspectFit
                                Layout.preferredWidth: 24
                                Layout.preferredHeight: 24
                            }

                            StyledText {
                                text: `#${modelData.workspace?.id ?? "?"}`
                                color: Appearance.colors.colSubtext
                                Layout.preferredWidth: 28
                                horizontalAlignment: Text.AlignHCenter
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0

                                StyledText {
                                    text: modelData.title || modelData.class || "Unknown application"
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }

                                StyledText {
                                    text: `${modelData.class || "Unknown"} · PID ${modelData.pid}`
                                    color: Appearance.colors.colSubtext
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                            }
                        }
                    }
                }

                StyledText {
                    visible: HyprlandData.windowList.length === 0
                    text: "No hay aplicaciones abiertas."
                    color: Appearance.colors.colSubtext
                    Layout.alignment: Qt.AlignHCenter
                }
            }
        }
    }
}
