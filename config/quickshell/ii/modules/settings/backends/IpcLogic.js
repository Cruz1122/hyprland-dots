.pragma library

// Pure helpers of IpcBackend: argv construction, `qs ipc show` parsing and
// value encoding. No QML types, so tests/qml_settings drive it directly.

// Settings stored in the main shell, reached over IPC. `read` returns the
// current value, `write` takes it as its only argument.
var KEYS = {
    "ipc.notifications.silent": {
        target: "notifications",
        read: "isSilent",
        write: "setSilent",
        type: "bool",
        defaultValue: false
    }
};

// Fire-and-forget calls used by settings pages (name -> target/function).
// Names are camelCase so page sources never carry dotted literals.
var CALLS = {
    regionRecord: { target: "region", fn: "record" },
    aiQuotaPanelToggle: { target: "aiQuotaPanel", fn: "toggle" },
    aiQuotaConnect: { target: "aiQuotaPanel", fn: "connectProvider", args: ["string"] }
};

var AI_PROVIDERS = ["codex", "opencode", "antigravity", "zed", "cursor", "claude"];

var NAME_RE = /^[A-Za-z_][A-Za-z0-9_]*$/;

// shellDir: directory of the running config (shell.qml lives there).
function baseArgv(shellDir) {
    return ["qs", "-p", String(shellDir), "ipc"];
}

function showArgv(shellDir) {
    return baseArgv(shellDir).concat(["show"]);
}

// Returns the argv of `qs ipc call`, or null when a name or argument is not
// safe to pass (IPC arguments are plain argv items, never shell text).
function callArgv(shellDir, target, fn, args) {
    if (!NAME_RE.test(String(target)) || !NAME_RE.test(String(fn)))
        return null;
    var out = baseArgv(shellDir).concat(["call", String(target), String(fn)]);
    var list = args || [];
    for (var i = 0; i < list.length; i++) {
        var encoded = encodeArg(list[i]);
        if (encoded === null)
            return null;
        out.push(encoded);
    }
    return out;
}

function encodeArg(value) {
    if (typeof value === "boolean")
        return value ? "true" : "false";
    if (typeof value === "number")
        return isFinite(value) ? String(value) : null;
    if (typeof value === "string") {
        // A leading "-" would be read as a qs option.
        if (value.length === 0 || value.charAt(0) === "-" || /[\u0000-\u001f]/.test(value))
            return null;
        return value;
    }
    return null;
}

// `qs ipc show` output -> { target: [function names] }.
function parseShow(text) {
    var targets = {};
    var current = null;
    var lines = String(text || "").split("\n");
    for (var i = 0; i < lines.length; i++) {
        var line = lines[i];
        var t = /^target\s+(\S+)\s*$/.exec(line);
        if (t) {
            current = t[1];
            targets[current] = [];
            continue;
        }
        var f = /^\s+function\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(/.exec(line);
        if (f && current !== null)
            targets[current].push(f[1]);
    }
    return targets;
}

function hasFunction(targets, target, fn) {
    var fns = targets ? targets[target] : null;
    return !!fns && fns.indexOf(fn) >= 0;
}

// Output of a `call` to a typed read function -> { ok, value }.
function decodeValue(type, text) {
    var s = String(text || "").trim();
    if (type === "bool") {
        if (s === "true")
            return { ok: true, value: true };
        if (s === "false")
            return { ok: true, value: false };
        return { ok: false };
    }
    if (type === "int" || type === "real") {
        if (s.length === 0 || !isFinite(Number(s)))
            return { ok: false };
        return { ok: true, value: type === "int" ? Math.round(Number(s)) : Number(s) };
    }
    return { ok: true, value: s };
}

function keySpec(key) {
    return KEYS.hasOwnProperty(key) ? KEYS[key] : null;
}

// argv that writes `value` for a registered key, or null.
function writeArgv(shellDir, key, value) {
    var spec = keySpec(key);
    if (!spec || !spec.write)
        return null;
    if (spec.type === "bool" && typeof value !== "boolean")
        return null;
    return callArgv(shellDir, spec.target, spec.write, [value]);
}

function readArgv(shellDir, key) {
    var spec = keySpec(key);
    return spec && spec.read ? callArgv(shellDir, spec.target, spec.read, []) : null;
}

// argv of a named page call (CALLS) with its arguments, or null.
function namedCallArgv(shellDir, name, args) {
    var spec = CALLS.hasOwnProperty(name) ? CALLS[name] : null;
    if (!spec)
        return null;
    var list = args || [];
    if (list.length !== (spec.args || []).length)
        return null;
    if (name === "aiQuotaConnect" && AI_PROVIDERS.indexOf(list[0]) < 0)
        return null;
    return callArgv(shellDir, spec.target, spec.fn, list);
}

// Whether the running shell exposes a named call.
function supportsCall(targets, name) {
    var spec = CALLS.hasOwnProperty(name) ? CALLS[name] : null;
    return !!spec && hasFunction(targets, spec.target, spec.fn);
}

// Capabilities published while the main shell answers: "mainShell" plus
// "ipc:<call name>" for every named call it exposes.
function capabilitiesFor(targets) {
    var caps = ["mainShell"];
    for (var name in CALLS) {
        if (supportsCall(targets, name))
            caps.push("ipc:" + name);
    }
    return caps;
}
