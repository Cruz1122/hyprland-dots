pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

// Clock card: time, weekday and date, the current week with today marked, and
// a bell that lights up with the unread notification count.
Rectangle {
    id: root
    readonly property date now: DateTime.clock.date
    readonly property var locale: Qt.locale()
    readonly property int unread: Notifications.unread
    readonly property bool weatherEnabled: Config.options?.bar.weather.enable ?? false
    // The seven days of the current week, starting on the locale's first day.
    readonly property var week: {
        const start = new Date(now.getFullYear(), now.getMonth(), now.getDate());
        const offset = (start.getDay() - locale.firstDayOfWeek + 7) % 7;
        start.setDate(start.getDate() - offset);
        const days = [];
        for (let i = 0; i < 7; i++) {
            const day = new Date(start.getFullYear(), start.getMonth(), start.getDate() + i);
            days.push({
                letter: locale.dayName(day.getDay(), Locale.NarrowFormat).toUpperCase(),
                number: day.getDate(),
                today: i === offset
            });
        }
        return days;
    }
    function capitalized(text) {
        return text.length > 0 ? text.charAt(0).toUpperCase() + text.slice(1) : text;
    }

    radius: Appearance.rounding.normal
    color: Appearance.colors.colLayer1

    ColumnLayout {
        anchors {
            fill: parent
            leftMargin: 14
            rightMargin: 12
            topMargin: 8
            bottomMargin: 10
        }
        spacing: 4

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            StyledText {
                text: DateTime.time
                font.pixelSize: 32
                font.weight: Font.DemiBold
                font.family: Appearance.font.family.expressive
                color: Appearance.colors.colOnLayer1
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 0
                StyledText {
                    Layout.fillWidth: true
                    text: root.capitalized(root.locale.toString(root.now, "dddd"))
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colPrimary
                    elide: Text.ElideRight
                }
                StyledText {
                    Layout.fillWidth: true
                    text: root.locale.toString(root.now, "d MMM")
                        + (root.weatherEnabled ? ` · ${Weather.data?.temp ?? "--"}` : "")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    elide: Text.ElideRight
                }
            }

            Item { // Notification bell with unread badge
                Layout.alignment: Qt.AlignTop
                Layout.topMargin: 4
                implicitWidth: 24
                implicitHeight: 24
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: Notifications.silent ? "notifications_off" : "notifications"
                    fill: root.unread > 0 ? 1 : 0
                    iconSize: Appearance.font.pixelSize.larger
                    color: root.unread > 0 ? Appearance.colors.colOnLayer1 : Appearance.colors.colSubtext
                }
                Rectangle {
                    visible: root.unread > 0
                    anchors {
                        right: parent.right
                        top: parent.top
                        rightMargin: -4
                        topMargin: -3
                    }
                    width: Math.max(14, badgeText.implicitWidth + 6)
                    height: 14
                    radius: 7
                    color: Appearance.colors.colPrimary
                    StyledText {
                        id: badgeText
                        anchors.centerIn: parent
                        text: root.unread > 99 ? "99+" : root.unread
                        font.pixelSize: 9
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnPrimary
                    }
                }
            }
        }

        Item { Layout.fillHeight: true }

        RowLayout { // Current week
            Layout.fillWidth: true
            spacing: 0
            Repeater {
                model: root.week
                Item {
                    id: dayCell
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: 36
                    StyledText {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.top: parent.top
                        text: dayCell.modelData.letter
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: dayCell.modelData.today ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                    }
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        width: 22
                        height: 22
                        radius: 11
                        color: dayCell.modelData.today ? Appearance.colors.colPrimary : "transparent"
                        StyledText {
                            anchors.centerIn: parent
                            text: dayCell.modelData.number
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: dayCell.modelData.today ? Font.DemiBold : Font.Normal
                            color: dayCell.modelData.today ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1
                        }
                    }
                }
            }
        }
    }
}
