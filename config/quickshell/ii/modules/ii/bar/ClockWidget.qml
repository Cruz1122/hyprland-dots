import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

Item {
    id: root
    property bool borderless: Config.options.bar.borderless
    readonly property int currentHour: DateTime.clock.date.getHours()
    readonly property bool isDay: currentHour >= 7 && currentHour < 18
    readonly property color pillColor: isDay ? "#F6D77A" : Appearance.colors.colSecondaryContainer
    readonly property color pillContentColor: isDay ? "#514005" : "#E2E2E2"
    readonly property string timeIcon: {
        const hour = root.currentHour;
        if (hour >= 7 && hour < 12)
            return "sunny";
        if (hour >= 12 && hour < 18)
            return "routine";
        return "dark_mode";
    }

    implicitWidth: clockPill.implicitWidth
    implicitHeight: Appearance.sizes.barHeight

    Rectangle {
        id: clockPill
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        implicitWidth: clockTextMask.implicitWidth + 12
        width: implicitWidth
        height: 18
        radius: height / 2
        color: root.pillColor

        Behavior on color {
            ColorAnimation {
                duration: 1000
                easing.type: Easing.InOutCubic
            }
        }

        Item {
            anchors.fill: parent

            RowLayout {
                id: clockTextMask
                anchors.centerIn: parent
                height: parent.height
                spacing: 2

                MaterialSymbol {
                    id: timeIcon
                    Layout.alignment: Qt.AlignVCenter
                    Layout.leftMargin: 2
                    Layout.rightMargin: 2
                    text: root.timeIcon
                    animateChange: true
                    iconSize: Appearance.font.pixelSize.smaller
                    fill: 1
                    color: root.pillContentColor

                    Behavior on color {
                        ColorAnimation {
                            duration: 1000
                            easing.type: Easing.InOutCubic
                        }
                    }
                }

                StyledText {
                    id: timeText
                    Layout.alignment: Qt.AlignVCenter
                font.pixelSize: 13
                font.weight: Font.Medium
                verticalAlignment: Text.AlignVCenter
                    color: root.pillContentColor
                    text: DateTime.time

                    Behavior on color {
                        ColorAnimation {
                            duration: 1000
                            easing.type: Easing.InOutCubic
                        }
                    }
                }
            }
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: !Config.options.bar.tooltips.clickToShow

        ClockWidgetPopup {
            hoverTarget: mouseArea
        }
    }
}
