.pragma library

// Read-only view of the Hyprland app variables (config/hypr/hyprland/
// variables.lua, overridden by ~/.config/hypr/custom/variables.lua). Only
// plain `name = "string"` assignments are understood; anything else is
// ignored rather than evaluated, since this is a display, not a Lua runtime.

var VARIABLES = ["terminal", "fileManager", "browser", "codeEditor", "textEditor", "officeSoftware",
                 "volumeMixer", "taskManager", "settingsApp"];

var ASSIGNMENT = /^\s*([A-Za-z_]\w*)\s*=\s*(?:"((?:\\.|[^"\\])*)"|'((?:\\.|[^'\\])*)')\s*(?:--.*)?$/;

function unescapeLua(text) {
    return text.replace(/\\(.)/g, function (_, c) {
        return c === "n" ? "\n" : c === "t" ? "\t" : c;
    });
}

function parseVariables(text) {
    var out = {};
    var lines = String(text || "").split("\n");
    for (var i = 0; i < lines.length; i++) {
        var m = ASSIGNMENT.exec(lines[i]);
        if (m && VARIABLES.indexOf(m[1]) >= 0)
            out[m[1]] = unescapeLua(m[2] !== undefined ? m[2] : m[3]);
    }
    return out;
}

function merge(base, override) {
    var out = {};
    var name;
    for (name in base)
        out[name] = base[name];
    for (name in override)
        out[name] = override[name];
    return out;
}

// launch_first_available.sh 'a' 'b' -> "a, b"; other commands unchanged.
function summarize(command) {
    var text = String(command || "");
    if (text.indexOf("launch_first_available.sh") < 0)
        return text;
    var options = [];
    var re = /'([^']*)'|"([^"]*)"/g;
    var after = text.slice(text.indexOf("launch_first_available.sh"));
    var m;
    while ((m = re.exec(after)) !== null)
        options.push(m[1] !== undefined ? m[1] : m[2]);
    return options.length > 0 ? options.join(", ") : text;
}

function infoValues(variables, prefix) {
    var out = {};
    for (var i = 0; i < VARIABLES.length; i++) {
        var name = VARIABLES[i];
        if (variables[name] !== undefined)
            out[prefix + name] = summarize(variables[name]);
    }
    return out;
}
