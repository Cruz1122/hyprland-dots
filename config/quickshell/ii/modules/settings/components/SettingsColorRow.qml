import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

// Hex color (#RRGGBB) with a live swatch; empty means automatic.
SettingsTextRow {
    id: row

    controlPreferredWidth: 220
    placeholder: Translation.tr("Automatic")

    Rectangle {
        Layout.alignment: Qt.AlignVCenter
        Layout.preferredWidth: 28
        Layout.preferredHeight: 28
        radius: 14
        border.width: 1
        border.color: Appearance.colors.colOutlineVariant
        color: /^#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$/.test(row.field.text) ? row.field.text : "transparent"

        MaterialSymbol {
            anchors.centerIn: parent
            visible: parent.color.a === 0
            text: "auto_awesome"
            iconSize: 16
            color: Appearance.colors.colSubtext
        }
    }
}
