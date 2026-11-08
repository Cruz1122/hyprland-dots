import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import "../core/SettingsLogic.js" as Logic

// List of strings as removable chips plus an "add" field. Every change
// commits the whole list.
SettingsRow {
    id: row

    readonly property var items: Logic.isArrayLike(row.value) ? Array.from(row.value).map(String) : []

    stacked: true
    controlFillsWidth: true
    activateHandler: () => addField.forceActiveFocus()
    interactHandler: () => false

    function removeAt(index) {
        const next = row.items.slice();
        next.splice(index, 1);
        row.commit(next);
    }

    function add() {
        const text = addField.text.trim();
        if (text.length === 0)
            return;
        if (row.items.includes(text)) {
            addField.invalid = true;
            return;
        }
        addField.invalid = !row.commit(row.items.concat([text]));
        if (!addField.invalid)
            addField.text = "";
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 10

        Flow {
            Layout.fillWidth: true
            visible: row.items.length > 0
            spacing: 6

            Repeater {
                model: row.items

                delegate: Rectangle {
                    id: chip
                    required property string modelData
                    required property int index
                    implicitHeight: 32
                    implicitWidth: chipRow.implicitWidth + 20
                    radius: 8
                    color: Appearance.colors.colSecondaryContainer

                    RowLayout {
                        id: chipRow
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: 12
                        spacing: 2

                        StyledText {
                            text: chip.modelData
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colOnSecondaryContainer
                        }

                        SettingsIconButton {
                            size: 24
                            iconSize: 16
                            iconName: "close"
                            iconColor: Appearance.colors.colOnSecondaryContainer
                            tooltip: Translation.tr("Remove “%1”").arg(chip.modelData)
                            onClicked: row.removeAt(chip.index)
                        }
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            SettingsTextField {
                id: addField
                Layout.fillWidth: true
                placeholderText: Translation.tr("Add an item")
                Accessible.name: Translation.tr("Add an item")
                onAccepted: row.add()
                onTextEdited: addField.invalid = false
            }

            SettingsButton {
                text: Translation.tr("Add")
                iconName: "add"
                enabled: addField.text.trim().length > 0
                onClicked: row.add()
            }
        }
    }
}
