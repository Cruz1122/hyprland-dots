import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs.modules.settings.core

// Non-blocking notice for failed writes; hides itself after a few seconds.
Rectangle {
    id: root

    property string message: ""
    property bool shown: false

    objectName: "settingsErrorToast"
    implicitWidth: Math.min(layout.implicitWidth + 32, 560)
    implicitHeight: layout.implicitHeight + 20
    radius: SettingsMetrics.cardRadius
    color: Appearance.colors.colErrorContainer
    visible: opacity > 0
    opacity: root.shown ? 1 : 0
    Accessible.role: Accessible.AlertMessage
    Accessible.name: root.message

    Behavior on opacity {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    Connections {
        target: SettingsStore
        function onFailed(key, message) {
            const label = SettingsRegistry.entry(key)?.label;
            root.message = label ? `${Translation.tr(label)}: ${Translation.tr(message)}` : Translation.tr(message);
            root.shown = true;
            hideTimer.restart();
        }
    }

    Timer {
        id: hideTimer
        interval: 5000
        onTriggered: root.shown = false
    }

    RowLayout {
        id: layout
        anchors {
            left: parent.left
            right: parent.right
            verticalCenter: parent.verticalCenter
            leftMargin: 16
            rightMargin: 8
        }
        spacing: 10

        MaterialSymbol {
            text: "error"
            iconSize: 20
            color: Appearance.colors.colOnErrorContainer
        }

        StyledText {
            Layout.fillWidth: true
            text: root.message
            wrapMode: Text.Wrap
            color: Appearance.colors.colOnErrorContainer
        }

        SettingsIconButton {
            iconName: "close"
            iconColor: Appearance.colors.colOnErrorContainer
            tooltip: Translation.tr("Dismiss")
            size: 30
            iconSize: 18
            onClicked: root.shown = false
        }
    }
}
