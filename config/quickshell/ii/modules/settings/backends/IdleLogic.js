.pragma library

// Pure logic for IdleBackend: idle.* timeouts (seconds, 0 = never) rendered
// by scripts/settings/idlegen.py.

var KEYS = ["idle.lockTimeout", "idle.dpmsTimeout", "idle.suspendTimeout"];
var FLAGS = { "idle.lockTimeout": "--lock", "idle.dpmsTimeout": "--dpms", "idle.suspendTimeout": "--suspend" };
// Must equal MARKER in scripts/settings/idlegen.py (tests compare them).
var IDLE_MARKER = "# managed by the settings app (scripts/settings/idlegen.py); manual edits are overwritten";
var MIN_TIMEOUT = 30;
var MAX_TIMEOUT = 86400;

// Same order rule as idlegen.py: lock <= dpms <= suspend among non-zero values.
// Returns "" or an English message.
function orderProblem(values) {
    var lock = values["idle.lockTimeout"] || 0;
    var dpms = values["idle.dpmsTimeout"] || 0;
    var suspend = values["idle.suspendTimeout"] || 0;
    for (var i = 0; i < KEYS.length; i++) {
        var v = values[KEYS[i]] || 0;
        if (typeof v !== "number" || Math.round(v) !== v || (v !== 0 && (v < MIN_TIMEOUT || v > MAX_TIMEOUT)))
            return "Use a time between 30 seconds and 24 hours";
    }
    if (lock && dpms && lock > dpms)
        return "The screen must lock before it turns off";
    if (dpms && suspend && dpms > suspend)
        return "The screen must turn off before the system suspends";
    if (lock && suspend && lock > suspend)
        return "The screen must lock before the system suspends";
    return "";
}

function withValue(values, key, value) {
    var next = {};
    for (var i = 0; i < KEYS.length; i++)
        next[KEYS[i]] = values[KEYS[i]] || 0;
    next[key] = value;
    return next;
}

// Registry options that keep the order valid for `key`; the current value
// always stays so the selector can show it.
function allowedChoices(options, values, key) {
    return (options || []).filter(function (o) {
        return o.value === values[key] || orderProblem(withValue(values, key, o.value)) === "";
    }).map(function (o) {
        return { value: o.value, label: o.label, icon: o.icon || "", translate: true };
    });
}

// hypridle.conf sources this exact path (`~` is HOME, not XDG_CONFIG_HOME).
function outputPath(home) {
    return home + "/.config/hypr/custom/shell-idle.conf";
}

// The page's Apply/Replace actions: render config.json as stored, restart hypridle.
function applyArgs(script, home, values, force) {
    return generatorArgs(script, outputPath(home), values, "write", force).concat(["--restart"]);
}

function generatorArgs(script, output, values, mode, force) {
    var args = ["python3", script];
    for (var i = 0; i < KEYS.length; i++)
        args.push(FLAGS[KEYS[i]], String(values[KEYS[i]] || 0));
    if (mode === "print")
        args.push("--print");
    else
        args.push("--output", output);
    if (force)
        args.push("--force");
    return args;
}

// Expected file text against what is on disk. A missing file means no
// listeners, which matches all-never.
// Returns "synced", "outOfSync" or "unmanaged" (exists without the marker).
function syncState(expected, actual, fileExists, allNever) {
    if (!fileExists)
        return allNever ? "synced" : "outOfSync";
    if (String(actual).split("\n")[0] !== IDLE_MARKER)
        return "unmanaged";
    return expected === actual ? "synced" : "outOfSync";
}

function allNever(values) {
    return KEYS.every(function (k) { return !values[k]; });
}
