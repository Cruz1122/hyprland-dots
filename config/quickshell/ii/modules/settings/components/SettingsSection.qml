import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

// Section title above a rounded card that holds the rows (default children).
// `bannerText` (translated) shows one notice at the top of the card, for
// example why every row of the section is unavailable.
ColumnLayout {
    id: root

    property string sectionId: ""
    property string title: ""
    property string icon: ""
    property string description: ""
    property string bannerText: ""
    default property alias content: card.data

    objectName: "section:" + root.sectionId
    spacing: 8

    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: 6
        spacing: 10
        visible: root.title.length > 0

        MaterialSymbol {
            visible: root.icon.length > 0
            text: root.icon
            iconSize: 20
            color: Appearance.colors.colPrimary
        }

        StyledText {
            Layout.fillWidth: true
            text: root.title
            wrapMode: Text.Wrap
            font.family: Appearance.font.family.title
            font.variableAxes: Appearance.font.variableAxes.title
            font.pixelSize: Appearance.font.pixelSize.larger
            color: Appearance.colors.colOnLayer1
        }
    }

    StyledText {
        visible: root.description.length > 0
        Layout.fillWidth: true
        Layout.leftMargin: 6
        Layout.bottomMargin: 2
        text: root.description
        wrapMode: Text.Wrap
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: Appearance.colors.colSubtext
    }

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: card.implicitHeight + 2 * SettingsMetrics.cardPadding
        radius: SettingsMetrics.cardRadius
        color: Appearance.colors.colLayer1

        ColumnLayout {
            id: card
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: SettingsMetrics.cardPadding
            }
            spacing: 2

            SettingsBannerRow {
                objectName: "sectionBanner:" + root.sectionId
                visible: root.bannerText.length > 0
                Layout.fillWidth: true
                iconName: "info"
                text: root.bannerText
            }
        }
    }
}
