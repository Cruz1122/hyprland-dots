import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import qs.services

// Multiple choice of screen names for a list entry; an empty list means
// every screen. Stored names of unplugged screens stay listed so they can
// be removed.
ColumnLayout {
    id: root

    property var row: null
    readonly property var stored: {
        const v = root.row?.value;
        return v && typeof v === "object" ? Array.from(v) : [];
    }
    readonly property var names: {
        const list = Quickshell.screens.map(s => s.name).filter(n => !!n);
        for (const name of root.stored) {
            if (name && !list.includes(name))
                list.push(name);
        }
        return list;
    }

    spacing: 6

    function toggle(name) {
        const next = root.stored.includes(name) ? root.stored.filter(n => n !== name) : root.stored.concat([name]);
        root.row?.commit(next);
    }

    Flow {
        Layout.fillWidth: true
        spacing: 6

        Repeater {
            model: root.names

            delegate: SettingsButton {
                required property string modelData
                readonly property bool selected: root.stored.includes(modelData)
                enabled: root.row?.rowEnabled ?? false
                kind: selected ? "filled" : "tonal"
                iconName: selected ? "check" : "monitor"
                text: Quickshell.screens.some(s => s.name === modelData) ? modelData : Translation.tr("%1 (not connected)").arg(modelData)
                Accessible.role: Accessible.CheckBox
                Accessible.checked: selected
                onClicked: root.toggle(modelData)
            }
        }
    }

    StyledText {
        Layout.fillWidth: true
        text: root.stored.length === 0 ? Translation.tr("No screen selected: the bar shows on every screen.") : ""
        visible: text.length > 0
        wrapMode: Text.Wrap
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: Appearance.colors.colSubtext
    }
}
