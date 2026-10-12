import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

MouseArea {
    id: root
    property bool borderless: Config.options.bar.borderless
    readonly property var chargeState: Battery.chargeState
    readonly property bool isCharging: Battery.isCharging
    readonly property bool chargingIndicator: isCharging || Battery.isFullyCharged
    readonly property bool isPluggedIn: Battery.isPluggedIn
    readonly property real percentage: Battery.percentage
    readonly property bool isLow: percentage <= Config.options.battery.low / 100

    implicitWidth: batteryPill.implicitWidth
    implicitHeight: Appearance.sizes.barHeight

    hoverEnabled: !Config.options.bar.tooltips.clickToShow

    Rectangle {
        id: batteryPill
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        implicitWidth: batteryContent.implicitWidth + 12
        width: implicitWidth
        height: 18
        radius: height / 2
        color: chargingIndicator ? "#F6D77A"
            : isLow ? Appearance.m3colors.m3error : Appearance.colors.colSecondaryContainer

        Behavior on color {
            ColorAnimation {
                duration: 300
                easing.type: Easing.InOutQuad
            }
        }

        RowLayout {
            id: batteryContent
            anchors.centerIn: parent
            height: parent.height
            spacing: 2

            MaterialSymbol {
                id: boltIcon
                Layout.alignment: Qt.AlignVCenter
                Layout.leftMargin: 2
                Layout.rightMargin: 2
                fill: 1
                text: "bolt"
                iconSize: Appearance.font.pixelSize.smaller
                color: chargingIndicator ? "#4A3900" : Appearance.colors.colOnSecondaryContainer
                visible: chargingIndicator
            }
            MaterialSymbol {
                id: batteryLevelIcon
                Layout.alignment: Qt.AlignVCenter
                Layout.leftMargin: 2
                Layout.rightMargin: 2
                fill: 1
                text: Icons.getBatteryIcon(Math.round(percentage * 100))
                iconSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colOnSecondaryContainer
                visible: !chargingIndicator
            }
            StyledText {
                Layout.alignment: Qt.AlignVCenter
                font.pixelSize: 13
                font.weight: Font.Medium
                verticalAlignment: Text.AlignVCenter
                color: chargingIndicator ? "#4A3900" : Appearance.colors.colOnSecondaryContainer
                text: Math.round(percentage * 100)
            }
        }
    }

    BatteryPopup {
        id: batteryPopup
        hoverTarget: root
    }
}
