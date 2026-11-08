.pragma library

// Pure helpers of HyprlandBackend and the Hyprland pages: value conversion
// between registry types and Hyprland, Lua literals for `hyprctl eval`, and
// parsers for hyprctl/xkb output. No QML objects, so tests/qml_settings can
// exercise it with plain qmltestrunner.

var EMPTY = "[[EMPTY]]";
var IDENT_RE = /^[A-Za-z_][A-Za-z0-9_]*$/;
var LUA_KEYWORDS = ["and", "break", "do", "else", "elseif", "end", "false", "for", "function", "goto", "if", "in",
    "local", "nil", "not", "or", "repeat", "return", "then", "true", "until", "while"];
// Same test as modules/common/models/quickToggles/GameModeToggle.qml.
var GAME_MODE_RE = /^\s*hl\.config\(\{\s*animations\s*=\s*\{\s*enabled\s*=/m;
// Modifier bits of `hyprctl -j binds` modmask, in display order.
var MODIFIERS = [[64, "Super"], [4, "Ctrl"], [8, "Alt"], [1, "Shift"], [2, "Caps"], [16, "Mod2"], [32, "Mod3"], [128, "Mod5"]];

function isControlFree(text) {
    return !/[\u0000-\u001f\u007f-\u009f]/.test(text);
}

function isLuaPath(path) {
    var parts = String(path).split(".");
    for (var i = 0; i < parts.length; i++) {
        if (!IDENT_RE.test(parts[i]) || LUA_KEYWORDS.indexOf(parts[i]) >= 0)
            return false;
    }
    return parts.length > 0;
}

// Key in custom/shell-settings.lua as hyprconfigurator.py lists it.
function overrideKey(path) {
    return String(path).split(".").join(":");
}

// Type hyprconfigurator.py and hl.config get for an entry. The registry type
// decides, not the default in `hyprctl -j descriptions`: floats with integral
// defaults (active_opacity, sensitivity, scroll_factor) are listed as ints.
function luaType(entry) {
    switch (entry.type) {
    case "bool": return "bool";
    case "int": return "int";
    case "real": return "float";
    case "enum": {
        var first = entry.options && entry.options.length > 0 ? entry.options[0].value : "";
        if (typeof first === "boolean")
            return "bool";
        if (typeof first === "number")
            return "int";
        return "string";
    }
    default: return "string";
    }
}

// Registry value -> the VALUE argument of `--set-typed KEY TYPE VALUE`.
// Lists (kb_layout, kb_options) are comma-joined strings in Hyprland.
function toArg(entry, value) {
    var type = luaType(entry);
    if (type === "bool")
        return value ? "true" : "false";
    if (type === "int")
        return String(Math.round(Number(value)));
    if (type === "float") {
        var n = Number(value);
        return Number.isInteger(n) ? n.toFixed(1) : String(n);
    }
    if (entry.type === "list")
        return toList(value).join(",");
    return String(value === undefined || value === null ? "" : value);
}

function toList(value) {
    if (value === undefined || value === null)
        return [];
    if (typeof value === "string")
        return value.split(",").map(function (s) { return s.trim(); }).filter(function (s) { return s.length > 0; });
    var out = [];
    for (var i = 0; i < value.length; i++)
        out.push(String(value[i]));
    return out;
}

function luaString(text) {
    return "\"" + String(text).replace(/\\/g, "\\\\").replace(/"/g, "\\\"") + "\"";
}

// Lua expression for `hyprctl eval`, or "" when path or value are unsafe.
function configExpression(entry, value) {
    if (!isLuaPath(entry.path))
        return "";
    var type = luaType(entry);
    var arg = toArg(entry, value);
    if (!isControlFree(arg))
        return "";
    var literal = type === "string" ? luaString(arg) : arg;
    if (type === "int" && !/^-?\d+$/.test(arg))
        return "";
    if (type === "float" && !isFinite(Number(arg)))
        return "";
    var parts = String(entry.path).split(".");
    var inner = parts[parts.length - 1] + " = " + literal;
    for (var i = parts.length - 2; i >= 0; i--)
        inner = parts[i] + " = { " + inner + " }";
    return "hl.config({ " + inner + " })";
}

// Hyprland value (descriptions `current`/`default`, or an override listed by
// hyprconfigurator.py) -> registry value.
function fromHypr(entry, raw) {
    if (raw === undefined || raw === null)
        return undefined;
    if (raw === EMPTY)
        raw = "";
    switch (entry.type) {
    case "bool":
        return raw === true || raw === 1 || raw === "true" || raw === "1";
    case "int":
        // Gaps are CSS-like ("5 5 5 5"); the int is applied to every side,
        // so the first side stands for all of them.
        if (typeof raw === "string")
            raw = parseInt(raw.trim().split(/\s+/)[0], 10);
        return isFinite(raw) ? Math.round(Number(raw)) : undefined;
    case "real": {
        var n = Number(raw);
        return isFinite(n) ? n : undefined;
    }
    case "enum": {
        var options = entry.options || [];
        for (var i = 0; i < options.length; i++) {
            var v = options[i].value;
            if (v === raw || (typeof v === "number" && Number(raw) === v && raw !== "") || (typeof v === "boolean" && fromHypr({ type: "bool" }, raw) === v))
                return v;
        }
        return typeof raw === "number" ? raw : String(raw);
    }
    case "list":
        return toList(String(raw));
    default:
        return String(raw);
    }
}

// `hyprctl -j descriptions` -> { name: { current, default } }.
function parseDescriptions(text) {
    var list = JSON.parse(text);
    var out = {};
    for (var i = 0; i < list.length; i++)
        out[list[i].name] = { current: list[i].current, "default": list[i]["default"] };
    return out;
}

// Hyprland lists touchpads among the mice of `hyprctl -j devices`.
function hasTouchpad(text) {
    var devices = JSON.parse(text);
    var mice = devices.mice || [];
    for (var i = 0; i < mice.length; i++) {
        if (/touchpad/i.test(mice[i].name || ""))
            return true;
    }
    return false;
}

function isGameModeActive(text) {
    return GAME_MODE_RE.test(String(text || ""));
}

// /usr/share/X11/xkb/rules/evdev.lst -> { layouts, variants, options }.
// layouts: [{ value, label }], variants: [{ value, layout, label }],
// options: [{ value, label }] (group headers without ':' are skipped).
function parseXkbList(text) {
    var out = { layouts: [], variants: [], options: [] };
    var section = "";
    var lines = String(text || "").split("\n");
    for (var i = 0; i < lines.length; i++) {
        var line = lines[i];
        var header = /^!\s*(\w+)/.exec(line);
        if (header) {
            section = header[1];
            continue;
        }
        var m = /^\s+(\S+)\s+(.*\S)\s*$/.exec(line);
        if (!m)
            continue;
        if (section === "layout") {
            out.layouts.push({ value: m[1], label: m[2] });
        } else if (section === "variant") {
            var v = /^([^:]+):\s*(.*)$/.exec(m[2]);
            if (v)
                out.variants.push({ value: m[1], layout: v[1], label: v[2] });
        } else if (section === "option" && m[1].indexOf(":") > 0) {
            out.options.push({ value: m[1], label: m[2] });
        }
    }
    out.layouts.sort(function (a, b) { return a.label.localeCompare(b.label); });
    return out;
}

function modifierNames(mask) {
    var names = [];
    for (var i = 0; i < MODIFIERS.length; i++) {
        if (mask & MODIFIERS[i][0])
            names.push(MODIFIERS[i][1]);
    }
    return names;
}

// `hyprctl -j binds` -> [{ keys, action, described }], described first.
// anyKeyLabel names the key of catch-all binds; the page passes it translated
// so that the shown text and the filter use the same words.
function parseBinds(text, anyKeyLabel) {
    var anyKey = anyKeyLabel === undefined ? "Any key" : String(anyKeyLabel);
    var list = JSON.parse(text);
    var out = [];
    for (var i = 0; i < list.length; i++) {
        var b = list[i];
        var key = b.key || (b.keycode ? "code:" + b.keycode : "");
        if (!key && !b.catch_all)
            continue;
        var keys = modifierNames(b.modmask || 0).concat([b.catch_all ? anyKey : key]).join(" + ");
        var action = b.has_description && b.description ? b.description : (b.dispatcher + (b.arg ? " " + b.arg : ""));
        out.push({ keys: (b.submap ? b.submap + ": " : "") + keys, action: action, described: !!b.has_description });
    }
    out.sort(function (a, b) { return (b.described - a.described) || a.keys.localeCompare(b.keys); });
    return out;
}

function filterBinds(binds, query) {
    var q = String(query || "").toLowerCase().trim();
    if (q.length === 0)
        return binds;
    var words = q.split(/\s+/);
    return binds.filter(function (b) {
        var hay = (b.keys + " " + b.action).toLowerCase();
        return words.every(function (w) { return hay.indexOf(w) >= 0; });
    });
}

// Raw value the dotfiles give an option (hyprbase.py `config`), or undefined.
// Registry options use getoption names; Lua-path names cover options whose
// getoption name differs (input:touchpad:tap-to-click is set as tap_to_click).
function baseRaw(entry, base) {
    if (!base)
        return undefined;
    if (entry.option !== undefined && Object.prototype.hasOwnProperty.call(base, entry.option))
        return base[entry.option];
    var key = overrideKey(entry.path);
    return Object.prototype.hasOwnProperty.call(base, key) ? base[key] : undefined;
}

// What a reset falls back to: the dotfiles' base value; Hyprland's compiled
// default when the base was read and nothing in the dotfiles sets the option;
// undefined (unknown) when the base could not be read.
function defaultFor(entry, base, baseLoaded, compiled) {
    if (!baseLoaded)
        return undefined;
    var raw = baseRaw(entry, base);
    return fromHypr(entry, raw !== undefined ? raw : (compiled || {})[entry.option]);
}

// Value the user has stored while Game Mode overrides the option: the
// shell-settings.lua override, else the base, else the compiled default.
function storedValue(entry, overrides, base, compiled) {
    var key = overrideKey(entry.path);
    if (overrides && Object.prototype.hasOwnProperty.call(overrides, key))
        return fromHypr(entry, overrides[key]);
    var raw = baseRaw(entry, base);
    return fromHypr(entry, raw !== undefined ? raw : (compiled || {})[entry.option]);
}

// Game Mode's overrides are `hyprconfigurator.py --list --json` of
// shellOverrides/main.lua (keys like "general:gaps_in").
function isPausedByGameMode(entry, gameMode, gameModeOverrides) {
    return !!gameMode && !!gameModeOverrides
        && Object.prototype.hasOwnProperty.call(gameModeOverrides, overrideKey(entry.path));
}

function isObject(value) {
    return !!value && typeof value === "object" && !Array.isArray(value);
}

// hyprbase.py output -> { ok, config, curves, animations }; anything
// unexpected is not ok. curves and animations feed AnimationBackend.
function parseBase(text) {
    try {
        var data = JSON.parse(text);
        if (data && data.ok === true && isObject(data.config))
            return {
                ok: true,
                config: data.config,
                curves: isObject(data.curves) ? data.curves : {},
                animations: isObject(data.animations) ? data.animations : {}
            };
    } catch (error) {
        // Truncated or non-JSON output: the base is unknown, as with ok=false.
    }
    return { ok: false, config: {}, curves: {}, animations: {} };
}
