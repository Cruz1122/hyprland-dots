import qs.modules.common
import qs.modules.common.widgets
import qs.services
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root

    NotificationListView { // Scrollable window
        id: listview
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: statusRow.bottom
        anchors.topMargin: 5
        anchors.bottom: parent.bottom

        clip: true
        layer.enabled: true
        layer.effect: OpacityMask {
            maskSource: Rectangle {
                width: listview.width
                height: listview.height
                radius: Appearance.rounding.normal
            }
        }

        popup: false
    }

    // Placeholder when list is empty
    PagePlaceholder {
        shown: Notifications.list.length === 0
        icon: "notifications_active"
        description: Translation.tr("Nothing")
        shape: MaterialShape.Shape.Ghostish
        descriptionHorizontalAlignment: Text.AlignHCenter
    }

    Item { // Header: title and count on the left, actions on the right
        id: statusRow
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
        }
        height: 36

        StyledText {
            id: titleText
            anchors {
                left: parent.left
                leftMargin: 4
                verticalCenter: parent.verticalCenter
            }
            text: Translation.tr("Notifications")
            font.pixelSize: Appearance.font.pixelSize.large
            font.weight: Font.DemiBold
            color: Appearance.colors.colOnLayer1
        }
        Rectangle { // Count badge
            anchors {
                left: titleText.right
                leftMargin: 8
                verticalCenter: parent.verticalCenter
            }
            visible: Notifications.list.length > 0
            width: Math.max(height, countText.implicitWidth + 12)
            height: 20
            radius: height / 2
            color: Appearance.colors.colPrimary
            StyledText {
                id: countText
                anchors.centerIn: parent
                text: Notifications.list.length
                font.family: Appearance.font.family.numbers
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colOnPrimary
            }
        }

        Row {
            anchors {
                right: parent.right
                verticalCenter: parent.verticalCenter
            }
            spacing: 4
            NotificationStatusButton {
                buttonIcon: "notifications_paused"
                toggled: Notifications.silent
                onClicked: () => {
                    Notifications.silent = !Notifications.silent;
                }
                StyledToolTip {
                    text: Translation.tr("Do not disturb")
                }
            }
            NotificationStatusButton {
                buttonIcon: "delete_sweep"
                enabled: Notifications.list.length > 0
                opacity: enabled ? 1 : 0.4
                onClicked: () => {
                    Notifications.discardAllNotifications()
                }
                StyledToolTip {
                    text: Translation.tr("Clear all")
                }
            }
        }
    }
}
