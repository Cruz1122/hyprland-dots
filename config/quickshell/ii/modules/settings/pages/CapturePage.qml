import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs.modules.settings.components
import "../backends/IpcLogic.js" as IpcLogic

SettingsPage {
    id: capturePage
    pageId: "capture"

    // record.sh toggles: starting while a recording runs stops it.
    actions: ({
        recordScreen: entry => Quickshell.execDetached([Directories.recordScriptPath, "--fullscreen"]),
        recordRegion: entry => {
            const argv = IpcLogic.namedCallArgv(Quickshell.shellPath(""), "regionRecord", []);
            if (argv)
                Quickshell.execDetached(argv);
        },
        pauseRecording: entry => Quickshell.execDetached([Directories.recordScriptPath, "--pause"]),
        stopRecording: entry => Quickshell.execDetached([Directories.recordScriptPath, "--stop"])
    })

    customDelegates: ({
        "screenRecord.systemAudioDevice": sinkPicker,
        "screenRecord.micDevice": sourcePicker
    })

    Component {
        id: sinkPicker
        AudioDevicePicker { sinks: true }
    }

    Component {
        id: sourcePicker
        AudioDevicePicker { sinks: false }
    }

    // record.sh takes a PipeWire node name (it appends ".monitor" for
    // outputs); an empty value follows the current default device.
    component AudioDevicePicker: RowLayout {
        id: picker
        property var row: null
        property bool sinks: true
        readonly property string stored: typeof picker.row?.value === "string" ? picker.row.value : ""
        readonly property var options: {
            const list = [{ value: "", label: Translation.tr("Default") }];
            for (const node of Pipewire.nodes.values) {
                if (!node || node.isStream || !node.audio || node.isSink !== picker.sinks)
                    continue;
                list.push({ value: node.name, label: node.description || node.nickname || node.name });
            }
            if (picker.stored.length > 0 && !list.some(o => o.value === picker.stored))
                list.push({ value: picker.stored, label: Translation.tr("%1 (not connected)").arg(picker.stored) });
            return list;
        }
        readonly property int currentIndex: Math.max(0, picker.options.findIndex(o => o.value === picker.stored))

        StyledComboBox {
            id: combo
            Layout.fillWidth: true
            Layout.maximumWidth: 420
            model: picker.options
            textRole: "label"
            Accessible.name: picker.row?.label ?? ""
            onActivated: index => {
                if (picker.row && !picker.row.commit(picker.options[index].value))
                    combo.currentIndex = picker.currentIndex;
            }
        }

        Binding {
            target: combo
            property: "currentIndex"
            value: picker.currentIndex
            restoreMode: Binding.RestoreNone
        }
    }
}
