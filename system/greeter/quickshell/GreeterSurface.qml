import QtQuick
import QtQuick.Effects
import Quickshell
import "TimeFormat.js" as TimeFormat

// Everything drawn on one screen. Only the `interactive` screen carries the
// login card and the corner pills; the others show the clock poster.
Item {
    id: root
    property bool interactive: true

    // Sizes are drawn for 1920 x 1080 and scale with the screen.
    readonly property real u: Math.min(width / 1920, height / 1080)

    // Entrance: everything rises into place once.
    property real reveal: 0
    Component.onCompleted: reveal = 1
    Behavior on reveal {
        NumberAnimation { duration: Theme.defaultSpatialDuration * 1.6; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.defaultSpatial }
    }

    function capitalized(text) {
        return text.charAt(0).toUpperCase() + text.slice(1);
    }

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.layer0
    }

    Image { // Optional snapshot of the desktop wallpaper, dimmed and blurred
        id: wallpaper
        anchors.fill: parent
        source: `file://${Theme.dir}/wallpaper`
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        visible: false
    }
    MultiEffect {
        anchors.fill: parent
        source: wallpaper
        visible: wallpaper.status === Image.Ready
        blurEnabled: true
        blur: 1
        blurMax: 64
        brightness: -0.45
        saturation: -0.3
    }

    Column { // Date and clock over the login card, centered as one block
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: (1 - root.reveal) * 50
        opacity: root.reveal
        spacing: 56 * root.u

        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 4 * root.u

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                // Letter spacing is also added after the last glyph; shift it back.
                anchors.horizontalCenterOffset: font.letterSpacing / 2
                readonly property bool spanish: Qt.locale().name.startsWith("es")
                text: `${root.capitalized(Qt.locale().toString(clock.date, "dddd"))}, ${Qt.locale().toString(clock.date, spanish ? "d 'de' MMMM" : "d MMMM")}`.toUpperCase()
                color: Theme.subtext
                font.family: Theme.titleFont
                font.pixelSize: 22 * root.u
                font.weight: Font.Bold
                font.letterSpacing: 8 * root.u
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                // The shell's time format, with its 12-hour "h:mm" handled.
                text: TimeFormat.formatTime(clock.date, Theme.user.timeFormat || "hh:mm", false, false, (date, format) => Qt.locale().toString(date, format))
                color: Theme.ink
                font.family: Theme.titleFont
                font.pixelSize: 200 * root.u
                font.weight: Font.Bold
                renderType: Text.NativeRendering
            }
        }

        LoginCard {
            id: card
            visible: root.interactive
            anchors.horizontalCenter: parent.horizontalCenter
            Component.onCompleted: focusField()
        }
    }

    Rectangle { // Session pill, bottom left
        visible: root.interactive
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.margins: 28
        height: 52
        width: sessionRow.implicitWidth + 16
        radius: height / 2
        color: Theme.layer1
        border.width: 1
        border.color: Theme.outline
        opacity: root.reveal

        Row {
            id: sessionRow
            anchors.centerIn: parent
            spacing: 2
            PillButton {
                anchors.verticalCenter: parent.verticalCenter
                icon: "chevron_left"
                label: Theme.tr("Session")
                visible: Sessions.sessions.length > 1
                onClicked: Sessions.cycle(-1)
            }
            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8
                leftPadding: 6
                rightPadding: 6
                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "desktop_windows"
                    color: Theme.subtext
                    size: 20
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Sessions.current.name
                    color: Theme.ink
                    font.family: Theme.titleFont
                    font.pixelSize: 15
                    font.weight: Font.Medium
                }
            }
            PillButton {
                anchors.verticalCenter: parent.verticalCenter
                icon: "chevron_right"
                label: Theme.tr("Session")
                visible: Sessions.sessions.length > 1
                onClicked: Sessions.cycle(1)
            }
        }
    }

    Rectangle { // Power pill, bottom right
        visible: root.interactive
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 28
        height: 52
        width: powerRow.implicitWidth + 16
        radius: height / 2
        color: Theme.layer1
        border.width: 1
        border.color: Theme.outline
        opacity: root.reveal

        Row {
            id: powerRow
            anchors.centerIn: parent
            spacing: 2
            PillButton {
                icon: "dark_mode"
                label: Theme.tr("Suspend")
                onClicked: Auth.suspend()
            }
            PillButton {
                icon: "restart_alt"
                label: Theme.tr("Restart")
                onClicked: Auth.reboot()
            }
            PillButton {
                icon: "power_settings_new"
                label: Theme.tr("Shut down")
                onClicked: Auth.poweroff()
            }
        }
    }

    MouseArea { // Clicking anywhere returns focus to the password
        anchors.fill: parent
        z: -1
        enabled: root.interactive
        onPressed: card.focusField()
    }
}
