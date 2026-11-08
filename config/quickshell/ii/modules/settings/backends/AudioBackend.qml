import QtQuick
import Quickshell.Services.Pipewire
import "AudioLogic.js" as AudioLogic

// Default output and input devices through Quickshell.Services.Pipewire.
// Values are node names (stable across restarts); writes set the preferred
// default so WirePlumber remembers the choice.
QtObject {
    id: root

    readonly property string name: "audio"
    readonly property bool available: Pipewire.ready
    readonly property string unavailableReason: Pipewire.ready ? "" : "PipeWire is not running"
    readonly property var values: ({
        "audio.output": Pipewire.defaultAudioSink?.name ?? "",
        "audio.input": Pipewire.defaultAudioSource?.name ?? ""
    })
    readonly property var capabilities: Pipewire.ready ? ["pipewire"] : []

    signal succeeded(string key)
    signal failed(string key, string message)

    function nodes() {
        return Pipewire.nodes.values;
    }

    function read(entry) { return root.values[entry.path ?? entry.key]; }
    function defaultValue(entry) { return undefined; }
    function isModified(entry) { return false; }

    function choices(entry) {
        const sink = AudioLogic.isSinkEntry(entry);
        return AudioLogic.choices(root.nodes(), sink, sink ? Pipewire.defaultAudioSink : Pipewire.defaultAudioSource);
    }

    function write(entry, value) {
        const sink = AudioLogic.isSinkEntry(entry);
        const node = AudioLogic.find(root.nodes(), sink, String(value));
        if (!node) {
            root.failed(entry.key, "The device is no longer available");
            return false;
        }
        if (sink)
            Pipewire.preferredDefaultAudioSink = node;
        else
            Pipewire.preferredDefaultAudioSource = node;
        root.succeeded(entry.key);
        return true;
    }

    function reset(entry) { return true; }
    function snapshot(entries) { return entries.map(e => ({ entry: e, value: root.read(e) })); }
    function preview(entry, value) { return root.write(entry, value); }
    function persist(entries) { return true; }
    function restore(snap) {
        let ok = true;
        for (const item of snap)
            ok = (!item.value || root.write(item.entry, item.value)) && ok;
        return ok;
    }
}
