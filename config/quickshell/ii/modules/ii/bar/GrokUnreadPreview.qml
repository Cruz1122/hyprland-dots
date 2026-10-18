import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root

    readonly property var unreadBots: GrokBots.unreadBots
    readonly property int iconSize: 32
    readonly property int iconSpacing: 4

    visible: unreadBots.length > 0
    implicitWidth: visible ? unreadBots.length * (iconSize + iconSpacing) - iconSpacing : 0
    implicitHeight: visible ? iconSize : 0
    Layout.alignment: Qt.AlignVCenter
    Layout.fillWidth: false

    Row {
        anchors.fill: parent
        spacing: root.iconSpacing

        Repeater {
            model: root.unreadBots

            delegate: Button {
                id: botButton
                required property var modelData

                implicitWidth: root.iconSize
                implicitHeight: root.iconSize
                padding: 0
                hoverEnabled: true
                Accessible.name: `${modelData.name}: ${modelData.unreadCount} mensajes sin leer`
                onClicked: GrokBots.openBot(modelData.id)

                HoverHandler {
                    cursorShape: Qt.PointingHandCursor
                }

                background: Item {}

                contentItem: Item {
                    Rectangle {
                        id: hoverHalo
                        anchors.centerIn: avatarMotion
                        width: avatarMotion.width + 6
                        height: avatarMotion.height + 6
                        radius: width / 2
                        color: "transparent"
                        border.width: 1
                        border.color: Appearance.colors.colPrimary
                        opacity: botButton.hovered ? 0.34 : 0
                        scale: botButton.hovered ? 1 : 0.82

                        Behavior on opacity {
                            NumberAnimation {
                                duration: 140
                                easing.type: Easing.OutCubic
                            }
                        }

                        Behavior on scale {
                            NumberAnimation {
                                duration: 180
                                easing.type: Easing.OutCubic
                            }
                        }
                    }

                    Item {
                        id: avatarMotion
                        anchors.centerIn: parent
                        width: 26
                        height: 26
                        property real introScale: 1
                        property real interactionScale: botButton.down ? 0.92 : (botButton.hovered ? 1.08 : 1)
                        scale: introScale * interactionScale

                        Behavior on scale {
                            NumberAnimation {
                                duration: 180
                                easing.type: Easing.OutCubic
                            }
                        }

                        GrokAvatar {
                            id: botAvatar
                            anchors.fill: parent
                            bot: modelData
                            nativeAnimationState: botButton.down
                                ? "excited"
                                : (botButton.hovered ? "curious" : "neutral")
                            size: 26
                        }

                        SequentialAnimation {
                            running: true

                            NumberAnimation {
                                target: avatarMotion
                                property: "introScale"
                                from: 0.72
                                to: 1.12
                                duration: 140
                                easing.type: Easing.OutBack
                            }

                            NumberAnimation {
                                target: avatarMotion
                                property: "introScale"
                                to: 1
                                duration: 100
                                easing.type: Easing.OutCubic
                            }
                        }
                    }

                    Rectangle {
                        anchors.left: parent.left
                        anchors.leftMargin: -6
                        anchors.top: parent.top
                        implicitWidth: Math.max(16, unreadCount.implicitWidth + 8)
                        implicitHeight: 16
                        radius: Appearance.rounding.full
                        color: Appearance.colors.colSecondaryContainer
                        border.width: 1
                        border.color: Appearance.colors.colLayer1

                        StyledText {
                            id: unreadCount
                            anchors.centerIn: parent
                            text: Number(modelData.unreadCount) > 99 ? "99+" : String(modelData.unreadCount)
                            color: Appearance.m3colors.m3onSecondaryContainer
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            font.weight: Font.DemiBold
                        }
                    }
                }
            }
        }
    }
}
