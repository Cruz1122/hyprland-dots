.pragma library
.import "../../common/functions/DisplayRules.js" as DisplayRules

// Pure monitor-layout logic for DisplayBackend and DisplaysPage.
//
// A layout ("spec") is the list monitorsgen.py accepts:
// [{ name, enabled, mode, position, scale, transform, mirror, vrr, bitdepth }]
// where position is "auto" or { x, y } and vrr is null when the output follows
// misc:vrr. `infos` are the raw objects from `hyprctl -j monitors all`.

// Must equal MARKER in scripts/settings/monitorsgen.py (tests compare them).
var MONITORS_MARKER = "-- managed by the settings app (scripts/settings/monitorsgen.py); manual edits are overwritten";

var SCALE_CANDIDATES = [1, 1.2, 1.25, 1.333333, 1.5, 1.6, 1.666667, 1.75, 2, 2.4, 2.5, 3];

var TRANSFORMS = [
    { value: 0, label: "Normal" },
    { value: 1, label: "90°" },
    { value: 2, label: "180°" },
    { value: 3, label: "270°" },
    { value: 4, label: "Flipped" },
    { value: 5, label: "Flipped, 90°" },
    { value: 6, label: "Flipped, 180°" },
    { value: 7, label: "Flipped, 270°" }
];

// null leaves the output on the global misc:vrr (Windows and effects).
var VRR_MODES = [
    { value: null, label: "Use the global setting" },
    { value: 0, label: "Off" },
    { value: 1, label: "On" },
    { value: 2, label: "Fullscreen only" }
];

function isInternal(name) {
    return /^(eDP|LVDS|DSI)-/.test(String(name));
}

function _copy(spec) {
    return spec.map(function (m) {
        var c = {};
        for (var k in m)
            c[k] = m[k];
        if (m.position && typeof m.position === "object")
            c.position = { x: m.position.x, y: m.position.y };
        return c;
    });
}

function _info(infos, name) {
    for (var i = 0; i < (infos || []).length; i++) {
        if (infos[i].name === name)
            return infos[i];
    }
    return null;
}

function _find(spec, name) {
    for (var i = 0; i < spec.length; i++) {
        if (spec[i].name === name)
            return spec[i];
    }
    return null;
}

function _round(value) {
    return Number(Number(value).toFixed(6));
}

// Hyprland reports mirrorOf as the source monitor id, or "none".
function mirrorName(infos, mirrorOf) {
    if (mirrorOf === undefined || mirrorOf === null || mirrorOf === "none" || mirrorOf === "")
        return null;
    for (var i = 0; i < infos.length; i++) {
        if (String(infos[i].id) === String(mirrorOf) || infos[i].name === mirrorOf)
            return infos[i].name;
    }
    return null;
}

// `fileVrr` ({ output: mode }, from vrrFromManagedText) supplies per-output
// VRR: hyprctl only reports whether VRR is active right now, and writing that
// back as a per-output mode would override misc:vrr (fullscreen-only VRR
// reads as off outside fullscreen). Outputs without one keep following it.
function specFromMonitors(infos, fileVrr) {
    var sorted = (infos || []).slice().sort(function (a, b) { return a.id - b.id; });
    var vrrByName = fileVrr || {};
    return sorted.map(function (m) {
        var enabled = !m.disabled;
        return {
            name: m.name,
            enabled: enabled,
            mode: enabled ? DisplayRules.modeFor(m, m.width, m.height, m.refreshRate) : "preferred",
            position: enabled ? { x: m.x, y: m.y } : "auto",
            scale: enabled && m.scale >= 0.25 ? _round(m.scale) : 1,
            transform: enabled ? (m.transform || 0) : 0,
            mirror: mirrorName(sorted, m.mirrorOf),
            vrr: Object.prototype.hasOwnProperty.call(vrrByName, m.name) ? vrrByName[m.name] : null,
            bitdepth: /2101010/.test(m.currentFormat || "") ? 10 : null
        };
    });
}

function parseMode(mode) {
    var match = /^(\d+)x(\d+)@(\d+(?:\.\d+)?)(Hz)?$/.exec(String(mode));
    return match ? { width: Number(match[1]), height: Number(match[2]), rate: Number(match[3]) } : null;
}

function modeLabel(mode) {
    var parsed = parseMode(mode);
    if (!parsed)
        return null;
    return parsed.width + " × " + parsed.height + " · " + Math.round(parsed.rate) + " Hz";
}

// Pixel size of a monitor's mode; "preferred" falls back to the current size.
function modeSize(monitor, info) {
    var parsed = parseMode(monitor.mode);
    if (parsed)
        return { width: parsed.width, height: parsed.height };
    return { width: info ? info.width : 0, height: info ? info.height : 0 };
}

function logicalSize(monitor, info) {
    var size = modeSize(monitor, info);
    var scale = monitor.scale > 0 ? monitor.scale : 1;
    var swap = (monitor.transform || 0) % 2 === 1;
    return {
        width: Math.round((swap ? size.height : size.width) / scale),
        height: Math.round((swap ? size.width : size.height) / scale)
    };
}

function positionOf(monitor, info) {
    if (monitor.position && typeof monitor.position === "object")
        return monitor.position;
    return { x: info ? info.x : 0, y: info ? info.y : 0 };
}

// Unique available modes, highest resolution and rate first.
function modeChoices(info, current) {
    var seen = {};
    var modes = [];
    var all = (info && info.availableModes ? Array.from(info.availableModes) : []).concat(current && current !== "preferred" ? [current] : []);
    for (var i = 0; i < all.length; i++) {
        if (!seen[all[i]] && parseMode(all[i])) {
            seen[all[i]] = true;
            modes.push(all[i]);
        }
    }
    modes.sort(function (a, b) {
        var pa = parseMode(a), pb = parseMode(b);
        return (pb.width * pb.height - pa.width * pa.height) || (pb.rate - pa.rate);
    });
    return [{ value: "preferred", label: "Preferred" }].concat(modes.map(function (m) {
        return { value: m, label: modeLabel(m), translate: false };
    }));
}

// Scales that give a whole logical size for the mode, plus the current one.
function scaleChoices(width, height, current) {
    var values = SCALE_CANDIDATES.filter(function (s) {
        if (!(width > 0 && height > 0))
            return s === 1 || s === 1.5 || s === 2;
        var w = width / s, h = height / s;
        return Math.abs(w - Math.round(w)) < 0.01 && Math.abs(h - Math.round(h)) < 0.01;
    });
    if (typeof current === "number" && !values.some(function (s) { return Math.abs(s - current) < 0.001; }))
        values.push(_round(current));
    values.sort(function (a, b) { return a - b; });
    return values.map(function (s) {
        return { value: s, label: Math.round(s * 100) + "%", translate: false };
    });
}

function enabledCount(spec) {
    return spec.filter(function (m) { return m.enabled; }).length;
}

// Arrangement of `name` relative to the others: "auto", "mirror:<n>",
// "right:<n>", "left:<n>", "above:<n>", "below:<n>" or "custom".
function arrangement(spec, infos, name) {
    var self = _find(spec, name);
    if (!self)
        return "auto";
    if (self.mirror)
        return "mirror:" + self.mirror;
    if (self.position === "auto")
        return "auto";
    var pos = positionOf(self, _info(infos, name));
    var size = logicalSize(self, _info(infos, name));
    var others = spec.filter(function (m) { return m.name !== name && m.enabled && !m.mirror; });
    for (var i = 0; i < others.length; i++) {
        var o = others[i];
        var oi = _info(infos, o.name);
        var op = positionOf(o, oi);
        var os = logicalSize(o, oi);
        if (pos.x === op.x + os.width && pos.y === op.y)
            return "right:" + o.name;
        if (pos.x === op.x - size.width && pos.y === op.y)
            return "left:" + o.name;
        if (pos.y === op.y - size.height && pos.x === op.x)
            return "above:" + o.name;
        if (pos.y === op.y + os.height && pos.x === op.x)
            return "below:" + o.name;
    }
    // A lone monitor at the origin is the trivial arrangement.
    if (others.length === 0 && pos.x === 0 && pos.y === 0)
        return "auto";
    return "custom";
}

// Option values for the arrangement selector; labels are built by the page.
function arrangementChoices(spec, name, current) {
    var values = ["auto"];
    var others = spec.filter(function (m) { return m.name !== name; });
    for (var i = 0; i < others.length; i++) {
        var o = others[i].name;
        values.push("right:" + o, "left:" + o, "above:" + o, "below:" + o);
        if (!others[i].mirror)
            values.push("mirror:" + o);
    }
    if (current === "custom")
        values.push("custom");
    return values;
}

function applyArrangement(spec, infos, name, value) {
    var next = _copy(spec);
    var self = _find(next, name);
    if (!self || value === "custom")
        return next;
    var parts = String(value).split(":");
    var relation = parts[0];
    var otherName = parts.slice(1).join(":");
    self.mirror = null;
    if (relation === "auto") {
        self.position = "auto";
        return next;
    }
    var other = _find(next, otherName);
    if (!other || otherName === name)
        return next;
    self.enabled = true;
    if (relation === "mirror") {
        self.mirror = otherName;
        return next;
    }
    var oi = _info(infos, otherName);
    var op = positionOf(other, oi);
    var os = logicalSize(other, oi);
    var size = logicalSize(self, _info(infos, name));
    if (relation === "right")
        self.position = { x: op.x + os.width, y: op.y };
    else if (relation === "left")
        self.position = { x: op.x - size.width, y: op.y };
    else if (relation === "above")
        self.position = { x: op.x, y: op.y - size.height };
    else if (relation === "below")
        self.position = { x: op.x, y: op.y + os.height };
    return next;
}

// Sets one field of one monitor. Refuses to disable the last enabled
// output (returns null) so a layout always keeps an image somewhere.
function setField(spec, name, field, value) {
    var next = _copy(spec);
    var self = _find(next, name);
    if (!self)
        return null;
    self[field] = value;
    if (field === "enabled" && value === false) {
        if (enabledCount(next) === 0)
            return null;
        for (var i = 0; i < next.length; i++) {
            if (next[i].mirror === name)
                next[i].mirror = null;
        }
    }
    if (field === "enabled" && value === true && self.position === undefined)
        self.position = "auto";
    return next;
}

function _source(spec) {
    var internal = spec.filter(function (m) { return isInternal(m.name); })[0];
    return internal || spec[0];
}

// Places `names` left to right from x = 0 in that order.
function _row(next, infos, names) {
    var x = 0;
    for (var i = 0; i < names.length; i++) {
        var m = _find(next, names[i]);
        m.position = { x: x, y: 0 };
        x += logicalSize(m, _info(infos, m.name)).width;
    }
}

function _enableAll(next, names) {
    for (var i = 0; i < next.length; i++) {
        var on = names.indexOf(next[i].name) >= 0;
        next[i].enabled = on;
        next[i].mirror = null;
        if (!on)
            next[i].position = "auto";
    }
}

function availablePresets(spec) {
    var internal = spec.filter(function (m) { return isInternal(m.name); }).length;
    var external = spec.length - internal;
    var presets = [];
    if (spec.length >= 2)
        presets.push("extend", "mirror");
    if (internal > 0 && external > 0)
        presets.push("internal", "external");
    return presets;
}

function preset(spec, infos, kind) {
    var next = _copy(spec);
    if (availablePresets(spec).indexOf(kind) < 0)
        return null;
    var source = _source(next);
    var internals = next.filter(function (m) { return isInternal(m.name); }).map(function (m) { return m.name; });
    var externals = next.filter(function (m) { return !isInternal(m.name); }).map(function (m) { return m.name; });
    if (kind === "extend") {
        var order = [source.name].concat(next.map(function (m) { return m.name; }).filter(function (n) { return n !== source.name; }));
        _enableAll(next, order);
        _row(next, infos, order);
    } else if (kind === "mirror") {
        _enableAll(next, next.map(function (m) { return m.name; }));
        source.position = { x: 0, y: 0 };
        var size = modeSize(source, _info(infos, source.name));
        var prefix = size.width + "x" + size.height + "@";
        for (var i = 0; i < next.length; i++) {
            var m = next[i];
            if (m.name === source.name)
                continue;
            var info = _info(infos, m.name);
            var modes = info && info.availableModes ? Array.from(info.availableModes) : [];
            var match = modes.filter(function (mode) { return mode.indexOf(prefix) === 0; })[0];
            m.mirror = source.name;
            m.mode = match || "preferred";
            // 1:1 avoids the target's DPI zooming the mirrored desktop.
            m.scale = 1;
            m.position = "auto";
        }
    } else if (kind === "internal") {
        _enableAll(next, internals);
        _row(next, infos, internals);
    } else if (kind === "external") {
        _enableAll(next, externals);
        _row(next, infos, externals);
    }
    return next;
}

function validate(spec) {
    if (!Array.isArray(spec) || spec.length === 0)
        return "No displays found";
    if (enabledCount(spec) === 0)
        return "At least one display must stay on";
    return "";
}

function specJson(spec) {
    return JSON.stringify({ monitors: spec });
}

// hyprland.lua requires this exact path (HOME, not XDG_CONFIG_HOME).
function outputPath(home) {
    return home + "/.config/hypr/monitors.lua";
}

function generatorArgs(script, output, spec, mode, force) {
    var args = ["python3", script];
    if (mode === "expr")
        args.push("--lua-expr");
    else
        args.push("--output", output);
    if (force)
        args.push("--force");
    args.push("--spec-json", specJson(spec));
    return args;
}

function isManagedText(text) {
    return String(text).split("\n")[0] === MONITORS_MARKER;
}

// Per-output VRR stated in a managed monitors.lua (monitorsgen.py lines):
// { output name: mode }. Outputs written without `vrr` are absent.
function vrrFromManagedText(text) {
    var out = {};
    if (!isManagedText(text))
        return out;
    var line = /^hl\.monitor\(\{ output = "((?:[^"\\]|\\.)*)", .*?\bvrr = (\d+)\b/;
    var lines = String(text).split("\n");
    for (var i = 0; i < lines.length; i++) {
        var match = line.exec(lines[i]);
        if (match)
            out[match[1].replace(/\\(.)/g, "$1")] = Number(match[2]);
    }
    return out;
}
