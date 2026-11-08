.pragma library

// Pure helpers for AudioBackend, testable without PipeWire
// (tests/qml_settings/tst_AudioLogic.qml). Nodes are PwNode-like objects:
// { name, description, nickname, isSink, isStream, audio }.

// Hardware devices of one direction. WirePlumber can expose the same HDMI
// profile repeatedly after a hotplug; those share a node name and are not
// separate choices, so keep one per name, preferring the current default.
function devices(nodes, isSink, preferred) {
    var unique = [];
    var list = nodes || [];
    for (var i = 0; i < list.length; i++) {
        var node = list[i];
        if (!node || !node.audio || node.isStream || node.isSink !== isSink || !node.name)
            continue;
        var at = -1;
        for (var j = 0; j < unique.length; j++) {
            if (unique[j].name === node.name) {
                at = j;
                break;
            }
        }
        if (at < 0)
            unique.push(node);
        else if (node === preferred)
            unique[at] = node;
    }
    return unique;
}

function label(node) {
    return node.description || node.nickname || node.name;
}

function choices(nodes, isSink, preferred) {
    return devices(nodes, isSink, preferred).map(function (node) {
        return { value: node.name, label: label(node), icon: isSink ? "speaker" : "mic" };
    });
}

function find(nodes, isSink, name) {
    var list = devices(nodes, isSink, null);
    for (var i = 0; i < list.length; i++) {
        if (list[i].name === name)
            return list[i];
    }
    return null;
}

// entry.path (or key) is "audio.output" or "audio.input".
function isSinkEntry(entry) {
    return (entry.path || entry.key) === "audio.output";
}
