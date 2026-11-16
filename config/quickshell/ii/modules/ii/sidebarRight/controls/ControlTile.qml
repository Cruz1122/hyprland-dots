import qs.services
import qs.modules.common
import qs.modules.common.models.quickToggles
import qs.modules.common.widgets
import QtQuick

// Quick-settings tile. The state lives in the icon bubble only, so a row of
// active toggles does not outweigh the rest of the rail. Toggles with a menu
// open it from the body and toggle from the bubble.
Rectangle {
    id: root
    property QuickToggleModel toggleModel
    signal openMenu()

    readonly property bool toggled: toggleModel?.toggled ?? false
    readonly property bool hasMenu: toggleModel?.hasMenu ?? false
    readonly property bool available: toggleModel?.available ?? true
    readonly property string statusText: (toggleModel?.hasStatusText ?? false)
        ? (toggleModel.statusText || (toggled ? Translation.tr("On") : Translation.tr("Off"))) : ""

    implicitHeight: 58
    radius: Appearance.rounding.normal
    color: bodyArea.containsPress ? Appearance.colors.colLayer1Active
        : bodyArea.containsMouse ? Appearance.colors.colLayer1Hover : Appearance.colors.colLayer1
    opacity: available ? 1 : 0.45
    Behavior on color {
        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
    }

    MouseArea {
        id: bodyArea
        anchors.fill: parent
        enabled: root.available
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onClicked: event => {
            if (root.hasMenu)
                root.openMenu();
            else if (event.button === Qt.RightButton && root.toggleModel?.altAction)
                root.toggleModel.altAction();
            else if (event.button === Qt.LeftButton)
                root.toggleModel?.mainAction();
        }
    }

    Rectangle {
        id: bubble
        anchors {
            left: parent.left
            leftMargin: 10
            verticalCenter: parent.verticalCenter
        }
        width: 38
        height: 38
        radius: width / 2
        color: root.toggled ? Appearance.colors.colPrimary
            : bubbleArea.containsMouse ? Appearance.colors.colLayer2Hover : Appearance.colors.colLayer2
        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        MaterialSymbol {
            anchors.centerIn: parent
            text: root.toggleModel?.icon ?? ""
            iconSize: 20
            fill: root.toggled ? 1 : 0
            color: root.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1
        }
        MouseArea { // With a menu on the body, the bubble is the on/off switch
            id: bubbleArea
            anchors.fill: parent
            enabled: root.hasMenu && root.available
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.toggleModel?.mainAction()
        }
    }

    Column {
        anchors {
            left: bubble.right
            leftMargin: 10
            right: chevron.visible ? chevron.left : parent.right
            rightMargin: chevron.visible ? 2 : 12
            verticalCenter: parent.verticalCenter
        }
        StyledText {
            width: parent.width
            elide: Text.ElideRight
            text: root.toggleModel?.name ?? ""
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colOnLayer1
        }
        StyledText {
            width: parent.width
            visible: text.length > 0
            elide: Text.ElideRight
            text: root.statusText
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }
    }

    MaterialSymbol {
        id: chevron
        anchors {
            right: parent.right
            rightMargin: 8
            verticalCenter: parent.verticalCenter
        }
        visible: root.hasMenu
        text: "chevron_right"
        iconSize: 18
        color: Appearance.colors.colSubtext
    }
}
