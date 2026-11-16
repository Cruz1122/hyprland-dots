import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.common.panels.lock
import "../../common/functions/TimeFormat.js" as TimeFormat

// Lock screen drawn like the greetd login (system/greeter/quickshell): date
// and clock over the avatar, name and password pill, centered as one block,
// with the keyboard and battery bottom left and power actions bottom right.
// Keep the two layouts in sync.
MouseArea {
    id: root
    required property LockContext context
    property bool active: false
    readonly property bool requirePasswordToPower: Config.options.lock.security.requirePasswordToPower

    // The login screen's identity snapshot (scripts/install-greeter.sh) names
    // the user and holds the avatar, so both screens show the same person.
    readonly property string greeterTheme: "/etc/greetd/quickshell/theme"
    property string displayName: SystemInfo.username

    function forceFieldFocus() {
        passwordBox.forceActiveFocus();
    }
    function capitalized(text) {
        return text.charAt(0).toUpperCase() + text.slice(1);
    }

    Connections {
        target: context
        function onShouldReFocus() {
            forceFieldFocus();
        }
    }
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton
    onPressed: mouse => forceFieldFocus()
    onPositionChanged: mouse => forceFieldFocus()

    // Entrance: the block rises into place.
    property real reveal: 0
    Behavior on reveal {
        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
    }
    Component.onCompleted: {
        forceFieldFocus();
        reveal = 1;
    }

    property bool ctrlHeld: false
    Keys.onPressed: event => {
        root.context.resetClearTimer();
        if (event.key === Qt.Key_Control)
            root.ctrlHeld = true;
        if (event.key === Qt.Key_Escape)
            root.context.currentText = "";
        forceFieldFocus();
    }
    Keys.onReleased: event => {
        if (event.key === Qt.Key_Control)
            root.ctrlHeld = false;
        forceFieldFocus();
    }

    FileView {
        path: `${root.greeterTheme}/user.json`
        onLoaded: {
            try {
                const user = JSON.parse(text());
                if (user.displayName)
                    root.displayName = user.displayName;
            } catch (e) {
                console.warn(`[LockSurface] ${path} is not valid JSON: ${e}`);
            }
        }
        // No greeter installed: keep the account name.
        onLoadFailed: error => {}
    }

    Rectangle { // Opaque, like the login screen
        anchors.fill: parent
        color: Appearance.colors.colLayer0
    }

    ColumnLayout { // Date and clock over the card, centered as one block
        anchors.centerIn: parent
        anchors.verticalCenterOffset: (1 - root.reveal) * 50
        opacity: root.reveal
        spacing: 56

        ColumnLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 4

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                // Letter spacing is also added after the last glyph; shift it back.
                Layout.leftMargin: font.letterSpacing
                readonly property bool spanish: Qt.locale().name.startsWith("es")
                text: `${root.capitalized(Qt.locale().toString(DateTime.clock.date, "dddd"))}, ${Qt.locale().toString(DateTime.clock.date, spanish ? "d 'de' MMMM" : "d MMMM")}`.toUpperCase()
                color: Appearance.colors.colOnSurfaceVariant
                font.family: Appearance.font.family.title
                font.pixelSize: 22
                font.weight: Font.Bold
                font.letterSpacing: 8
            }
            StyledText {
                Layout.alignment: Qt.AlignHCenter
                // Formatted like the login screen: DateTime.time adds seconds
                // to "h:mm" while locked, a rule of the old lock clock.
                text: TimeFormat.formatTime(DateTime.clock.date, Config.options?.time.format ?? "hh:mm",
                    Config.options?.time.secondPrecision === true, false, (date, format) => Qt.locale().toString(date, format))
                color: Appearance.colors.colOnLayer0
                font.family: Appearance.font.family.title
                font.pixelSize: 200
                font.weight: Font.Bold
                renderType: Text.NativeRendering
            }
        }

        ColumnLayout { // Avatar, name, password
            Layout.alignment: Qt.AlignHCenter
            spacing: 18

            ClippingRectangle {
                Layout.alignment: Qt.AlignHCenter
                implicitWidth: 104
                implicitHeight: 104
                radius: width / 2
                color: Appearance.colors.colLayer2

                StyledText {
                    anchors.centerIn: parent
                    visible: avatar.status !== Image.Ready
                    text: root.displayName.charAt(0).toUpperCase()
                    font.family: Appearance.font.family.title
                    font.pixelSize: 44
                    font.weight: Font.DemiBold
                }
                Image {
                    id: avatar
                    // Greeter snapshot first, then ~/.face, then the picture SDDM used.
                    property list<string> candidates: [`file://${root.greeterTheme}/avatar`, `${Directories.home}/.face`, `file:///usr/share/sddm/faces/${SystemInfo.username}.face.icon`]
                    property int candidate: 0
                    anchors.fill: parent
                    source: candidates[candidate]
                    fillMode: Image.PreserveAspectCrop
                    sourceSize: Qt.size(208, 208)
                    asynchronous: true
                    onStatusChanged: {
                        if (status === Image.Error && candidate + 1 < candidates.length)
                            candidate++;
                    }
                }
            }

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                Layout.leftMargin: font.letterSpacing
                text: root.displayName.toUpperCase()
                font.family: Appearance.font.family.title
                font.pixelSize: 17
                font.weight: Font.DemiBold
                font.letterSpacing: 5
            }

            RowLayout { // Holds the pill so ErrorShakeAnimation can move its margin
                Layout.alignment: Qt.AlignHCenter

                Rectangle {
                    id: pill
                    implicitWidth: 380
                    implicitHeight: 56
                    radius: height / 2
                    color: Appearance.colors.colLayer1
                    border.width: 1
                    border.color: Appearance.colors.colOutlineVariant

                    ErrorShakeAnimation {
                        id: wrongPasswordShakeAnim
                        target: pill
                        distance: 14
                    }
                    Connections {
                        target: GlobalStates
                        function onScreenUnlockFailedChanged() {
                            if (GlobalStates.screenUnlockFailed)
                                wrongPasswordShakeAnim.restart();
                        }
                    }

                    MaterialSymbol {
                        id: leadIcon
                        anchors.left: parent.left
                        anchors.leftMargin: 20
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.context.fingerprintsConfigured ? "fingerprint" : "lock"
                        iconSize: Appearance.font.pixelSize.huge
                        color: Appearance.colors.colSubtext
                    }

                    TextInput {
                        id: passwordBox
                        anchors.left: leadIcon.right
                        anchors.leftMargin: 14
                        anchors.right: confirm.left
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        height: parent.height
                        clip: true
                        verticalAlignment: TextInput.AlignVCenter
                        echoMode: TextInput.Password
                        inputMethodHints: Qt.ImhSensitiveData
                        enabled: !root.context.unlockInProgress
                        // Drawn by PasswordChars; the real glyphs and cursor stay hidden.
                        color: "transparent"
                        selectionColor: "transparent"
                        selectedTextColor: "transparent"
                        cursorDelegate: Item {}
                        font.pixelSize: Appearance.font.pixelSize.normal

                        // Synchronized across monitors through the context.
                        onTextChanged: root.context.currentText = text
                        onAccepted: root.context.tryUnlock(root.ctrlHeld)
                        Connections {
                            target: root.context
                            function onCurrentTextChanged() {
                                passwordBox.text = root.context.currentText;
                            }
                        }
                        Keys.onPressed: event => root.context.resetClearTimer()

                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: passwordBox.text.length === 0
                            text: GlobalStates.screenUnlockFailed ? Translation.tr("Incorrect password") : Translation.tr("Enter password")
                            color: GlobalStates.screenUnlockFailed ? Appearance.colors.colError : Appearance.colors.colSubtext
                            font.family: Appearance.font.family.title
                            font.pixelSize: Appearance.font.pixelSize.normal
                        }
                        PasswordChars {
                            anchors.fill: parent
                            // Its cursor would sit on the placeholder.
                            visible: Config.options.lock.materialShapeChars && root.context.currentText.length > 0
                            length: root.context.currentText.length
                            selectionStart: passwordBox.selectionStart
                            selectionEnd: passwordBox.selectionEnd
                            cursorPosition: passwordBox.cursorPosition
                            color: Appearance.colors.colOnLayer0
                        }
                        StyledText { // Plain dots when shaped characters are off
                            anchors.verticalCenter: parent.verticalCenter
                            visible: !Config.options.lock.materialShapeChars
                            text: "●".repeat(root.context.currentText.length)
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
                        color: Appearance.colors.colOnLayer0
                        opacity: confirmArea.pressed ? 0.8 : 1
                        scale: confirmArea.pressed ? 0.92 : 1
                        Behavior on scale {
                            animation: Appearance.animation.clickBounce.numberAnimation.createObject(this)
                        }

                        MaterialSymbol {
                            anchors.centerIn: parent
                            iconSize: 24
                            color: Appearance.colors.colLayer0
                            text: {
                                if (root.context.unlockInProgress)
                                    return "hourglass_top";
                                if (root.context.targetAction === LockContext.ActionEnum.Poweroff)
                                    return "power_settings_new";
                                if (root.context.targetAction === LockContext.ActionEnum.Reboot)
                                    return "restart_alt";
                                return root.ctrlHeld ? "coffee" : "arrow_forward";
                            }
                        }
                        MouseArea {
                            id: confirmArea
                            anchors.fill: parent
                            enabled: !root.context.unlockInProgress
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.context.tryUnlock(root.ctrlHeld)
                        }
                    }
                }
            }
        }
    }

    LockCornerPill { // Keyboard layout and battery, bottom left
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.margins: 28
        opacity: root.reveal

        RowLayout {
            spacing: 14
            Layout.leftMargin: 10
            Layout.rightMargin: 10
            LockIconText {
                icon: "keyboard_alt"
                text: HyprlandXkb.currentLayoutCode
            }
            LockIconText {
                visible: Battery.available
                icon: Battery.isCharging ? "bolt" : "battery_android_full"
                text: `${Math.round(Battery.percentage * 100)}%`
                color: (Battery.isLow && !Battery.isCharging) ? Appearance.colors.colError : Appearance.colors.colSubtext
            }
        }
    }

    LockCornerPill { // Power actions, bottom right
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 28
        opacity: root.reveal

        LockCornerButton {
            context: root.context
            requirePassword: root.requirePasswordToPower
            symbol: "dark_mode"
            onClicked: Session.suspend()
        }
        LockCornerButton {
            context: root.context
            requirePassword: root.requirePasswordToPower
            symbol: "power_settings_new"
            targetAction: LockContext.ActionEnum.Poweroff
        }
        LockCornerButton {
            context: root.context
            requirePassword: root.requirePasswordToPower
            symbol: "restart_alt"
            targetAction: LockContext.ActionEnum.Reboot
        }
    }
}
