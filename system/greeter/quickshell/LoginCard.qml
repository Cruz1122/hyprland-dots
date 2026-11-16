import QtQuick
import Quickshell
import Quickshell.Widgets

// Avatar, name and the password pill. Goes straight to the password: no
// "press any key" stage.
Column {
    id: root
    readonly property string username: Theme.user.name || Quickshell.env("USER") || ""
    readonly property string displayName: Theme.user.displayName || username

    function focusField() {
        field.forceActiveFocus();
    }
    function submit() {
        Auth.login(root.username, field.text, Sessions.current);
    }

    spacing: 18

    Connections {
        target: Auth
        function onFailuresChanged() {
            field.text = "";
            shake.restart();
            root.focusField();
        }
    }

    Item { // Avatar
        anchors.horizontalCenter: parent.horizontalCenter
        width: 104
        height: 104

        ClippingRectangle {
            anchors.fill: parent
            radius: width / 2
            color: Theme.layer2

            Text {
                anchors.centerIn: parent
                visible: avatar.status !== Image.Ready
                text: root.displayName.charAt(0).toUpperCase()
                color: Theme.ink
                font.family: Theme.titleFont
                font.pixelSize: 44
                font.weight: Font.DemiBold
            }
            Image {
                id: avatar
                anchors.fill: parent
                source: Theme.avatar
                fillMode: Image.PreserveAspectCrop
                sourceSize: Qt.size(208, 208)
                asynchronous: true
            }
        }
    }

    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: root.displayName.toUpperCase()
        color: Theme.ink
        font.family: Theme.titleFont
        font.pixelSize: 17
        font.weight: Font.DemiBold
        font.letterSpacing: 5
    }

    Item { // Password pill; shakes on a rejected password
        id: pillSlot
        anchors.horizontalCenter: parent.horizontalCenter
        width: 380
        height: 56

        Rectangle {
            id: pill
            width: parent.width
            height: parent.height
            radius: height / 2
            color: Theme.layer1
            border.width: 1
            border.color: Theme.outline

            Icon {
                id: lockIcon
                anchors.left: parent.left
                anchors.leftMargin: 20
                anchors.verticalCenter: parent.verticalCenter
                text: "lock"
                color: Theme.subtext
            }

            TextInput {
                id: field
                anchors.left: lockIcon.right
                anchors.leftMargin: 14
                anchors.right: confirm.left
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                height: parent.height
                verticalAlignment: TextInput.AlignVCenter
                echoMode: TextInput.Password
                inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText
                enabled: !Auth.busy
                // Drawn by PasswordDots; the real glyphs and cursor stay hidden.
                color: "transparent"
                selectionColor: "transparent"
                selectedTextColor: "transparent"
                cursorDelegate: Item {}
                font.pixelSize: 16
                focus: true
                onAccepted: root.submit()
                Keys.onEscapePressed: text = ""
                // A stale "incorrect password" reads wrong once typing resumes.
                onTextEdited: Auth.message = ""

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: field.text.length === 0
                    text: Auth.busy ? Theme.tr("Signing in") : Theme.tr("Password")
                    color: Theme.subtext
                    font.family: Theme.titleFont
                    font.pixelSize: 16
                }
                PasswordDots {
                    anchors.fill: parent
                    length: field.text.length
                }
            }

            Rectangle {
                id: confirm
                anchors.right: parent.right
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                width: 42
                height: 42
                radius: height / 2
                color: Theme.ink
                opacity: confirmArea.pressed ? 0.8 : 1
                scale: confirmArea.pressed ? 0.92 : 1
                Behavior on scale {
                    NumberAnimation { duration: Theme.fastSpatialDuration; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.fastSpatial }
                }

                Icon {
                    id: confirmIcon
                    anchors.centerIn: parent
                    text: Auth.busy ? "progress_activity" : "arrow_forward"
                    color: Theme.primaryInk
                    RotationAnimation on rotation {
                        running: Auth.busy
                        from: 0
                        to: 360
                        duration: 900
                        loops: Animation.Infinite
                        onStopped: confirmIcon.rotation = 0
                    }
                }
                MouseArea {
                    id: confirmArea
                    anchors.fill: parent
                    enabled: !Auth.busy
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.submit()
                }
            }
        }

        SequentialAnimation {
            id: shake
            readonly property real distance: 14
            NumberAnimation { target: pill; property: "x"; to: -shake.distance; duration: 50 }
            NumberAnimation { target: pill; property: "x"; to: shake.distance; duration: 70 }
            NumberAnimation { target: pill; property: "x"; to: -shake.distance / 2; duration: 70 }
            NumberAnimation { target: pill; property: "x"; to: 0; duration: 140; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.fastSpatial }
        }
    }

    Text { // PAM feedback
        anchors.horizontalCenter: parent.horizontalCenter
        height: 20
        text: Auth.message.length > 0 ? Auth.message : (Auth.preview ? Theme.tr("Preview: the password is \"demo\"") : "")
        color: Auth.messageIsError && Auth.message.length > 0 ? Theme.error : Theme.subtext
        font.family: Theme.titleFont
        font.pixelSize: 14
    }
}
