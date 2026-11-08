import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

// Intro of the Animations page (custom delegate of info.animations.intro):
// three boxes that say what each part of the page controls. Collapsible;
// open when the page is created.
ColumnLayout {
    id: root

    property var row: null
    property var entry: null
    property bool open: true
    readonly property var boxes: [
        {
            icon: "desktop_windows",
            title: Translation.tr("Desktop"),
            text: Translation.tr("Hyprland moves windows, workspaces and shell panels. The preset and the cards on this page change it.")
        },
        {
            icon: "touch_app",
            title: Translation.tr("Interface"),
            text: Translation.tr("The shell animates its own menus, switches and transitions. Only the last section of this page, “Motion inside the shell”, changes it.")
        },
        {
            icon: "sports_esports",
            title: Translation.tr("Game Mode"),
            text: Translation.tr("While it is on, desktop animations are off. Your values stay saved and come back when you turn it off.")
        }
    ]

    spacing: 10

    SettingsButton {
        objectName: "introToggle"
        kind: "text"
        iconName: root.open ? "expand_less" : "expand_more"
        text: root.open ? Translation.tr("Hide the explanation") : Translation.tr("Show the explanation")
        Accessible.checkable: true
        Accessible.checked: root.open
        onClicked: root.open = !root.open
        Keys.onReturnPressed: root.open = !root.open
        Keys.onEnterPressed: root.open = !root.open
    }

    GridLayout {
        objectName: "introBoxes"
        visible: root.open
        Layout.fillWidth: true
        columns: root.width >= 640 ? 3 : 1
        columnSpacing: 10
        rowSpacing: 10

        Repeater {
            model: root.boxes

            delegate: Rectangle {
                id: box
                required property var modelData
                required property int index

                objectName: "introBox:" + box.index
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: 1
                implicitHeight: boxLayout.implicitHeight + 24
                radius: SettingsMetrics.controlRadius
                color: Appearance.colors.colLayer2

                ColumnLayout {
                    id: boxLayout
                    anchors {
                        left: parent.left
                        right: parent.right
                        top: parent.top
                        margins: 12
                    }
                    spacing: 6

                    RowLayout {
                        spacing: 8

                        MaterialSymbol {
                            text: box.modelData.icon
                            iconSize: 20
                            color: Appearance.colors.colPrimary
                        }

                        StyledText {
                            text: box.modelData.title
                            font.weight: Font.Medium
                            color: Appearance.colors.colOnLayer2
                            Accessible.role: Accessible.Heading
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: box.modelData.text
                        wrapMode: Text.Wrap
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }
                }
            }
        }
    }
}
