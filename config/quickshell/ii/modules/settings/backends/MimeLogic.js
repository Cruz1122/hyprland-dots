.pragma library

// Pure helpers for MimeBackend: parse scripts/settings/default-apps.py output
// and turn it into store values and picker choices. Kept free of QML types so
// tests/qml_settings/tst_MimeLogic.qml can drive it directly.

var KEY_PREFIX = "mime.";

function roleOf(entry) {
    var path = entry.path || entry.key || "";
    return path.indexOf(KEY_PREFIX) === 0 ? path.slice(KEY_PREFIX.length) : path;
}

// Returns { ok, roles, error }. roles: { <role>: roleState } as printed by
// `default-apps.py list --json`.
function parseList(text) {
    var data;
    try {
        data = JSON.parse(text);
    } catch (e) {
        return { ok: false, roles: {}, error: "Unexpected output from the default applications helper" };
    }
    if (!data || typeof data !== "object" || !data.roles || typeof data.roles !== "object")
        return { ok: false, roles: {}, error: "Unexpected output from the default applications helper" };
    return { ok: true, roles: data.roles, error: "" };
}

// Returns { ok, role, state, error } for the output of `set ROLE ID`.
function parseSet(text) {
    var data;
    try {
        data = JSON.parse(text);
    } catch (e) {
        return { ok: false, role: "", state: null, error: "Unexpected output from the default applications helper" };
    }
    if (!data || !data.role || typeof data.role.role !== "string")
        return { ok: false, role: "", state: null, error: "Unexpected output from the default applications helper" };
    return { ok: true, role: data.role.role, state: data.role, error: "" };
}

function withRole(roles, role, state) {
    var next = {};
    for (var name in roles)
        next[name] = roles[name];
    next[role] = state;
    return next;
}

function valuesFrom(roles) {
    var values = {};
    for (var role in roles)
        values[KEY_PREFIX + role] = roles[role] && roles[role].current ? roles[role].current : "";
    return values;
}

// Picker options. Desktop icons are freedesktop theme names, not Material
// Symbols, so they are not passed to the combo box (it renders `icon` as a
// symbol ligature). The current default is kept even when it is not a
// candidate (NoDisplay apps, apps that skip the primary type) so the row
// still shows what is selected today.
function choices(state) {
    if (!state)
        return [];
    var out = [];
    var candidates = state.candidates || [];
    for (var i = 0; i < candidates.length; i++) {
        var c = candidates[i];
        out.push({ value: c.id, label: c.name || c.id });
    }
    if (state.current && !candidates.some(function (c) { return c.id === state.current; }))
        out.unshift({ value: state.current, label: state.currentName || state.current });
    return out;
}

// Last non-empty stderr line, without the helper's "default-apps: error: " prefix.
function errorMessage(stderr, fallback) {
    var lines = String(stderr || "").split("\n").filter(function (l) { return l.trim().length > 0; });
    for (var i = lines.length - 1; i >= 0; i--) {
        var match = /^default-apps: error: (.*)$/.exec(lines[i].trim());
        if (match)
            return match[1];
    }
    return lines.length > 0 ? lines[lines.length - 1].trim() : fallback;
}
