import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

// Drill-in page that takes over the right rail (Wi-Fi, Bluetooth): back button
// and title on the left of the header, page actions on the right, scrolling
// body, optional footer. Drop-in for WindowDialog in the rail's dialog
// loaders: same `show` / `dismiss()` contract, hidden once faded out.
Item {
    id: root
    property bool show: false
    property string title: ""
    // Thin progress line under the header.
    property bool busy: false
    property alias actions: actionRow.data
    property alias footer: footerRow.data
    default property alias content: body.data
    signal dismiss()

    readonly property real padding: 16
    property real presence: show ? 1 : 0
    Behavior on presence {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }
    visible: presence > 0

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape) {
            root.dismiss();
            event.accepted = true;
        }
    }

    MouseArea { // Nothing underneath reacts while the page is up
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        hoverEnabled: true
        onWheel: event => event.accepted = true
    }

    Rectangle {
        anchors.fill: parent
        opacity: root.presence
        transform: Translate { x: 28 * (1 - root.presence) }
        color: Appearance.colors.colLayer0
        // Matches the rail's rounded inner corner.
        bottomLeftRadius: Appearance.rounding.large + 10

        Item {
            id: header
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                leftMargin: root.padding - 6
                rightMargin: root.padding
                topMargin: root.padding
            }
            height: 36

            HeaderButton {
                id: backButton
                anchors.verticalCenter: parent.verticalCenter
                buttonIcon: "arrow_back"
                tooltip: Translation.tr("Back")
                onClicked: root.dismiss()
            }
            StyledText {
                anchors {
                    left: backButton.right
                    leftMargin: 6
                    verticalCenter: parent.verticalCenter
                }
                text: root.title
                font.pixelSize: Appearance.font.pixelSize.larger
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer0
            }
            Row {
                id: actionRow
                anchors {
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                }
                spacing: 8
            }
        }

        StyledIndeterminateProgressBar {
            anchors {
                left: parent.left
                right: parent.right
                top: header.bottom
                topMargin: 8
                leftMargin: root.padding
                rightMargin: root.padding
            }
            height: 3
            opacity: root.busy ? 1 : 0
            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
        }

        ColumnLayout {
            id: body
            anchors {
                left: parent.left
                right: parent.right
                top: header.bottom
                bottom: footerRow.top
                leftMargin: root.padding
                rightMargin: root.padding
                topMargin: 20
                bottomMargin: footerRow.visibleChildren.length > 0 ? 10 : 0
            }
            spacing: 8
        }

        Row {
            id: footerRow
            anchors {
                left: parent.left
                bottom: parent.bottom
                leftMargin: root.padding
                bottomMargin: root.padding
            }
            spacing: 8
        }
    }
}
