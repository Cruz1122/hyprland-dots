.pragma library

// Pure helpers of AnimationBackend and the Animations page (docs/settings.md,
// "Backends -> animation"): the 10 animation cards, style grammar, value
// validation, companion fades, presets, the curve catalog and summary parts.
// No QML objects, so tests/qml_settings exercises it with qmltestrunner.
//
// Validation mirrors scripts/settings/animationsgen.py, the only Lua
// serializer; both are tested against tests/fixtures/animation-cases.json.
// Every text field below (labels, descriptions) is an English source string
// for Translation.tr.

// Card id = registry entry path; key = "animation.<card>". Each card writes
// its primary leaf plus, for windows and layers, the fade leaf that runs with it.
var CARDS = [
    { id: "windowsIn", leaf: "windowsIn", companion: "fadeIn", family: "windows" },
    { id: "windowsOut", leaf: "windowsOut", companion: "fadeOut", family: "windows" },
    { id: "windowsMove", leaf: "windowsMove", companion: "", family: "windows" },
    { id: "workspaces", leaf: "workspaces", companion: "", family: "workspaces" },
    { id: "specialWorkspaceIn", leaf: "specialWorkspaceIn", companion: "", family: "workspaces" },
    { id: "specialWorkspaceOut", leaf: "specialWorkspaceOut", companion: "", family: "workspaces" },
    { id: "layersIn", leaf: "layersIn", companion: "fadeLayersIn", family: "layers" },
    { id: "layersOut", leaf: "layersOut", companion: "fadeLayersOut", family: "layers" },
    { id: "border", leaf: "border", companion: "", family: "none" },
    { id: "zoomFactor", leaf: "zoomFactor", companion: "", family: "none" }
];
var CARD_IDS = CARDS.map(function (c) { return c.id; });

// Hyprland 0.57 animation tree (src/config/shared/animation/AnimationTree.cpp).
// A node that nothing overrides takes every field from its nearest overridden
// ancestor.
var PARENTS = {
    windows: "global", layers: "global", fade: "global", border: "global", borderangle: "global",
    shadowangle: "global", glowangle: "global", workspaces: "global", zoomFactor: "global", monitorAdded: "global",
    windowsIn: "windows", windowsOut: "windows", windowsMove: "windows",
    layersIn: "layers", layersOut: "layers",
    fadeIn: "fade", fadeOut: "fade", fadeSwitch: "fade", fadeShadow: "fade", fadeGlow: "fade", fadeDim: "fade",
    fadeLayers: "fade", fadePopups: "fade", fadeDpms: "fade",
    fadeLayersIn: "fadeLayers", fadeLayersOut: "fadeLayers", fadePopupsIn: "fadePopups", fadePopupsOut: "fadePopups",
    workspacesIn: "workspaces", workspacesOut: "workspaces", specialWorkspace: "workspaces",
    specialWorkspaceIn: "specialWorkspace", specialWorkspaceOut: "specialWorkspace"
};
// Hyprland's compiled defaults (AnimationTree reset()): global is enabled,
// speed 8 (800 ms), bezier "default"; the *angle nodes are disabled. Every
// card leaf inherits from global, so without the dotfiles base each card
// resolves to { enabled: true, speed: 8, curve: "default", style: "" }.
var COMPILED = {
    global: { enabled: true, speed: 8, curve: "default", style: "" },
    borderangle: { enabled: false, speed: 1, curve: "default", style: "" },
    shadowangle: { enabled: false, speed: 1, curve: "default", style: "" },
    glowangle: { enabled: false, speed: 1, curve: "default", style: "" }
};

var BUILTIN_CURVES = [
    { name: "default", type: "bezier", points: [0, 0.75, 0.15, 1], label: "Hyprland standard", group: "hyprland", builtin: true },
    { name: "linear", type: "bezier", points: [0, 0, 1, 1], label: "Constant", group: "hyprland", builtin: true }
];
// Written to the generated file only while a card uses them.
var APP_SPRINGS = [
    { name: "ii_spring_soft", type: "spring", mass: 1, stiffness: 238.1191, damping: 24.21279333, label: "Soft spring", group: "app", builtin: true },
    { name: "ii_spring_bouncy", type: "spring", mass: 1, stiffness: 260, damping: 18, label: "Bouncy spring", group: "app", builtin: true }
];
// Friendly names of the dotfiles curves (config/hypr/hyprland/general.lua);
// the raw identifier only appears in help text. The bounce names follow how
// far each curve overshoots (peak y of the bezier): expressiveDefaultSpatial
// about 1.4 %, expressiveSlowSpatial 1.9 %, expressiveFastSpatial 9 %
// (tests/test_animation_texts.py).
var CURVE_LABELS = {
    emphasizedDecel: "Quick start, gentle stop",
    emphasizedAccel: "Speeding exit",
    standardDecel: "Standard stop",
    menu_decel: "Menu entrance",
    menu_accel: "Menu exit",
    stall: "Pause, then go",
    expressiveSlowSpatial: "Medium bounce",
    expressiveDefaultSpatial: "Light bounce",
    expressiveFastSpatial: "Strong bounce"
};

var IDENT_RE = /^[A-Za-z_][A-Za-z0-9_]*$/;
var USER_CURVE_RE = /^ii_[a-z0-9_]{1,32}$/;
var CONTROL_RE = /[\u0000-\u001f\u007f-\u009f\u2028\u2029]/;
var PERCENT_RE = /^(0|[1-9][0-9]{0,2})%$/;
var MAX_LABEL = 40;
var DIRECTIONS = ["top", "bottom", "left", "right"];
var STYLE_KINDS = {
    windows: ["slide", "popin", "gnomed"],
    workspaces: ["slide", "slidevert", "fade", "slidefade", "slidefadevert"],
    layers: ["fade", "slide", "popin"],
    none: []
};
var PERCENT_KINDS = { windows: ["popin"], layers: ["popin"], workspaces: ["slidefade", "slidefadevert"], none: [] };
var DIRECTION_KINDS = { windows: ["slide"], layers: ["slide"], workspaces: [], none: [] };
var STYLE_LABELS = {
    none: "Hyprland default",
    popin: "Pop in",
    slide: "Slide",
    gnomed: "GNOME style",
    fade: "Fade",
    slidevert: "Slide vertically",
    slidefade: "Slide and fade",
    slidefadevert: "Slide vertically and fade"
};
// By family: Hyprland animates a window or a panel (layer) on its own, but
// moves the whole workspace (src/animation/WorkspaceAnimationController.cpp:
// a slide shifts it by the screen width or height, a special workspace also
// fades), and the app offers no side for workspaces.
var STYLE_DESCRIPTIONS = {
    // The windows family also serves windowsMove, and Hyprland reads the
    // style only when a window opens or closes (the windowsIn/windowsOut
    // config, desktop/view/animationControllers/WindowAnimationController.cpp
    // in 0.57): a move never uses it, so the texts say so.
    windows: {
        slide: "A window opening or closing travels through a screen edge, the nearest unless you pick a side; moves ignore it.",
        popin: "A window opening or closing changes size from a smaller one with a fade (at 100% it only fades); moves ignore it.",
        gnomed: "A window opening or closing unfolds from a line across the middle, as in GNOME; moves ignore it."
    },
    layers: {
        fade: "Appears or disappears in place, without moving.",
        slide: "Moves in or out through a screen edge: the nearest one unless you pick a side.",
        popin: "Changes size from a smaller one with a fade; at 100% it only fades."
    },
    workspaces: {
        slide: "The whole workspace moves sideways, as far as the screen is wide; the auxiliary workspace (Super+S) also fades.",
        slidevert: "The whole workspace moves up or down, as far as the screen is tall; the auxiliary workspace (Super+S) also fades.",
        fade: "The workspace fades in or out in place, without moving.",
        slidefade: "The workspace moves sideways part of the way while it fades.",
        slidefadevert: "The workspace moves up or down part of the way while it fades."
    },
    none: {}
};

// Absolute presets (contracts §1): fields not listed keep the card's base
// value; companions are derived. "default" removes every animation line.
// The block between the markers is plain JSON: tests/test_animationsgen.py
// reads it so Python and QML test the same tables.
// presets-json-begin
var PRESETS = {
  "agile": {
    "windowsIn": { "speed": 2, "curve": "emphasizedDecel", "style": "popin 85%" },
    "windowsOut": { "speed": 1.4, "style": "popin 90%" },
    "windowsMove": { "speed": 2, "style": "slide" },
    "workspaces": { "speed": 4.5, "curve": "menu_decel", "style": "slide" },
    "specialWorkspaceIn": { "speed": 1.8 },
    "specialWorkspaceOut": { "speed": 0.8 },
    "layersIn": { "speed": 1.8 },
    "layersOut": { "speed": 1.6 },
    "border": { "speed": 6 },
    "zoomFactor": { "speed": 2 }
  },
  "smooth": {
    "windowsIn": { "speed": 4.5 },
    "windowsOut": { "speed": 3 },
    "windowsMove": { "speed": 4.5 },
    "workspaces": { "speed": 9 },
    "specialWorkspaceIn": { "speed": 4 },
    "specialWorkspaceOut": { "speed": 1.8 },
    "layersIn": { "speed": 4 },
    "layersOut": { "speed": 3.6 },
    "border": { "speed": 14 },
    "zoomFactor": { "speed": 4.5 }
  },
  "bouncy": {
    "windowsIn": { "speed": 4, "curve": "expressiveDefaultSpatial", "style": "popin 70%" },
    "windowsOut": { "speed": 2, "curve": "emphasizedAccel" },
    "windowsMove": { "speed": 4, "curve": "expressiveDefaultSpatial" },
    "workspaces": { "speed": 6, "curve": "expressiveSlowSpatial" },
    "specialWorkspaceIn": { "speed": 3.5, "curve": "expressiveDefaultSpatial" },
    "layersIn": { "speed": 3, "curve": "expressiveFastSpatial", "style": "popin 85%" },
    "zoomFactor": { "speed": 3, "curve": "expressiveFastSpatial" }
  },
  "minimal": {
    "windowsIn": { "speed": 1.5, "curve": "standardDecel", "style": "popin 100%" },
    "windowsOut": { "speed": 1, "style": "popin 100%" },
    "windowsMove": { "speed": 1.5 },
    "workspaces": { "speed": 2.5, "style": "fade" },
    "specialWorkspaceIn": { "speed": 1.5, "style": "fade" },
    "specialWorkspaceOut": { "speed": 1, "style": "fade" },
    "layersIn": { "speed": 1.5 },
    "layersOut": { "speed": 1.2 },
    "border": { "speed": 3 },
    "zoomFactor": { "speed": 1.5 }
  }
};
// presets-json-end
var PRESET_IDS = ["default", "agile", "smooth", "bouncy", "minimal"];
var PRESET_LABELS = {
    "default": "Default",
    agile: "Agile",
    smooth: "Smooth",
    bouncy: "Bouncy",
    minimal: "Minimal",
    custom: "Custom"
};
var PRESET_DESCRIPTIONS = {
    "default": "The dotfiles animations, without any change from this page.",
    agile: "Everything a bit faster, without bounces.",
    smooth: "Slower and more fluid.",
    bouncy: "Windows and panels overshoot a little before they settle.",
    minimal: "Short animations: windows and workspaces fade in and out; moved windows and the panels still move, only faster."
};

// ------------------------------------------------------------------ helpers

function plain(value) {
    return value === undefined ? undefined : JSON.parse(JSON.stringify(value));
}

function equal(a, b) {
    return JSON.stringify(sorted(a)) === JSON.stringify(sorted(b));
}

function sorted(value) {
    if (Array.isArray(value))
        return value.map(sorted);
    if (value && typeof value === "object") {
        var out = {};
        Object.keys(value).sort().forEach(function (k) { out[k] = sorted(value[k]); });
        return out;
    }
    return value;
}

function card(id) {
    for (var i = 0; i < CARDS.length; i++) {
        if (CARDS[i].id === id)
            return CARDS[i];
    }
    return null;
}

// Card id of a registry entry: its path, with or without the "animation." prefix.
function cardOf(entry) {
    var path = String(entry && (entry.path || entry.key) || "");
    if (path.indexOf("animation.") === 0)
        path = path.slice("animation.".length);
    return path;
}

function isNumber(value) {
    return typeof value === "number" && isFinite(value);
}

// floor(x * 100 + 0.5) / 100, the same expression as animationsgen.round2.
function round2(value) {
    return Math.floor(value * 100 + 0.5) / 100;
}

function durationMs(speed) {
    return Math.round(speed * 100);
}

function isUserCurveName(name) {
    return typeof name === "string" && USER_CURVE_RE.test(name) && !isAppSpring(name);
}

function isAppSpring(name) {
    return APP_SPRINGS.some(function (c) { return c.name === name; });
}

// "" when the label is acceptable, else an English reason.
function labelProblem(label) {
    if (typeof label !== "string" || label.replace(/ /g, "").length === 0)
        return "The name cannot be empty";
    if (CONTROL_RE.test(label))
        return "The name contains control characters";
    // Code points, as Python's len(): a surrogate pair counts once.
    if (label.replace(/[\uD800-\uDBFF][\uDC00-\uDFFF]/g, "_").length > MAX_LABEL)
        return "The name is longer than 40 characters";
    return "";
}

// ------------------------------------------------------------------- styles

function familyOf(cardId) {
    var c = card(cardId);
    return c ? c.family : "none";
}

// { kind, percent, direction, known, raw }. kind is one of none, popin,
// slide, slidevert, fade, slidefade, slidefadevert, gnomed; an unknown style
// keeps its text in `raw` with known = false so it is never lost.
function parseStyle(cardId, style) {
    var family = familyOf(cardId);
    var raw = String(style === undefined || style === null ? "" : style);
    var unknown = { kind: "none", percent: null, direction: "", known: false, raw: raw };
    if (typeof style !== "string" && style !== undefined && style !== null)
        return unknown;
    if (raw === "")
        return { kind: "none", percent: null, direction: "", known: true, raw: "" };
    var words = raw.split(" ");
    var kind = words[0];
    if (STYLE_KINDS[family].indexOf(kind) < 0 || words.length > 2)
        return unknown;
    var percent = null;
    var direction = "";
    if (words.length === 2) {
        var arg = words[1];
        if (PERCENT_KINDS[family].indexOf(kind) >= 0 && PERCENT_RE.test(arg)) {
            percent = parseInt(arg, 10);
            if (percent > 100)
                return unknown;
        } else if (DIRECTION_KINDS[family].indexOf(kind) >= 0 && DIRECTIONS.indexOf(arg) >= 0) {
            direction = arg;
        } else {
            return unknown;
        }
    }
    return { kind: kind, percent: percent, direction: direction, known: true, raw: raw };
}

// Inverse of parseStyle; an unknown parsed style gives back its raw text.
function formatStyle(cardId, parsed) {
    if (!parsed)
        return "";
    if (parsed.known === false)
        return String(parsed.raw ?? "");
    if (!parsed.kind || parsed.kind === "none")
        return "";
    var family = familyOf(cardId);
    var text = parsed.kind;
    if (PERCENT_KINDS[family].indexOf(parsed.kind) >= 0 && isNumber(parsed.percent))
        text += " " + Math.max(0, Math.min(100, Math.round(parsed.percent))) + "%";
    else if (DIRECTION_KINDS[family].indexOf(parsed.kind) >= 0 && DIRECTIONS.indexOf(parsed.direction) >= 0)
        text += " " + parsed.direction;
    return text;
}

// Styles a card offers: [{ kind, label, description, percent: bool, directions: [] }].
function styleOptions(cardId) {
    var family = familyOf(cardId);
    return STYLE_KINDS[family].map(function (kind) {
        return {
            kind: kind,
            label: STYLE_LABELS[kind],
            description: STYLE_DESCRIPTIONS[family][kind],
            percent: PERCENT_KINDS[family].indexOf(kind) >= 0,
            directions: DIRECTION_KINDS[family].indexOf(kind) >= 0 ? DIRECTIONS.slice() : []
        };
    });
}

// ------------------------------------------------------------------- curves

// Every curve a card may use: Hyprland built-ins, the dotfiles curves of the
// base (hyprbase.py "curves"), the app springs and the user's ii_* curves.
// [{ name, type, points | mass/stiffness/damping, label, group, builtin }].
function curveCatalog(base, userCurves) {
    var out = BUILTIN_CURVES.map(plain);
    var baseCurves = base && base.curves ? base.curves : {};
    Object.keys(baseCurves).sort().forEach(function (name) {
        if (isIgnoredBaseCurve(base, name) || out.some(function (c) { return c.name === name; }))
            return;
        var item = Object.assign({ name: name }, plain(baseCurves[name]));
        item.label = CURVE_LABELS[name] || name;
        item.group = "dotfiles";
        item.builtin = true;
        out.push(item);
    });
    out = out.concat(APP_SPRINGS.map(plain));
    var user = userCurves || {};
    Object.keys(user).sort().forEach(function (name) {
        if (!isUserCurveName(name))
            return;
        var item = plain(user[name]);
        item.name = name;
        item.label = typeof item.label === "string" && item.label.length > 0 ? item.label : name;
        item.group = "user";
        item.builtin = false;
        out.push(item);
    });
    return out;
}

function findCurve(catalog, name) {
    for (var i = 0; i < (catalog || []).length; i++) {
        if (catalog[i].name === name)
            return catalog[i];
    }
    return null;
}

function isSpring(catalog, name) {
    var c = findCurve(catalog, name);
    return !!c && c.type === "spring";
}

// ---------------------------------------------------------------- validation

// { ok, value, error } for a card value { enabled, speed, curve, style }.
function validateCard(cardId, value, catalog) {
    if (!card(cardId))
        return { ok: false, error: "Unknown animation" };
    if (!value || typeof value !== "object" || Array.isArray(value))
        return { ok: false, error: "Invalid animation value" };
    if (JSON.stringify(Object.keys(value).sort()) !== JSON.stringify(["curve", "enabled", "speed", "style"]))
        return { ok: false, error: "Invalid animation value" };
    if (typeof value.enabled !== "boolean")
        return { ok: false, error: "Invalid animation value" };
    if (!isNumber(value.speed) || !(value.speed > 0 && value.speed <= 100))
        return { ok: false, error: "The duration is out of range" };
    if (typeof value.curve !== "string" || !IDENT_RE.test(value.curve) || !findCurve(catalog, value.curve))
        return { ok: false, error: "Unknown curve" };
    if (typeof value.style !== "string" || !parseStyle(cardId, value.style).known)
        return { ok: false, error: "This style is not available for this animation" };
    return { ok: true, value: { enabled: value.enabled, speed: value.speed, curve: value.curve, style: value.style } };
}

var CURVE_FIELDS = ["name", "type", "points", "mass", "stiffness", "damping", "label", "group", "builtin"];

// { ok, value, error } for a user curve descriptor.
function validateCurve(name, desc) {
    if (!isUserCurveName(name))
        return { ok: false, error: "Invalid curve name" };
    if (!desc || typeof desc !== "object" || Array.isArray(desc))
        return { ok: false, error: "Invalid curve" };
    var keys = Object.keys(desc);
    for (var i = 0; i < keys.length; i++) {
        if (CURVE_FIELDS.indexOf(keys[i]) < 0)
            return { ok: false, error: "Invalid curve" };
    }
    if ("name" in desc && desc.name !== name)
        return { ok: false, error: "Invalid curve" };
    var problem = labelProblem(desc.label);
    if (problem)
        return { ok: false, error: problem };
    if (desc.type === "bezier") {
        if ("mass" in desc || "stiffness" in desc || "damping" in desc)
            return { ok: false, error: "Invalid curve" };
        var p = desc.points;
        if (!Array.isArray(p) || p.length !== 4 || !p.every(isNumber))
            return { ok: false, error: "Invalid curve" };
        if (!(p[0] >= 0 && p[0] <= 1 && p[2] >= 0 && p[2] <= 1))
            return { ok: false, error: "The curve points are out of range" };
        if (!(p[1] >= -1 && p[1] <= 2 && p[3] >= -1 && p[3] <= 2))
            return { ok: false, error: "The curve points are out of range" };
        return { ok: true, value: { name: name, type: "bezier", points: p.slice(), label: desc.label } };
    }
    if (desc.type === "spring") {
        if ("points" in desc)
            return { ok: false, error: "Invalid curve" };
        var out = { name: name, type: "spring", label: desc.label };
        var fields = ["mass", "stiffness", "damping"];
        for (var j = 0; j < fields.length; j++) {
            var v = desc[fields[j]];
            if (!isNumber(v) || !(v > 0.5 && v <= 10000))
                return { ok: false, error: "The spring values are out of range" };
            out[fields[j]] = v;
        }
        return { ok: true, value: out };
    }
    return { ok: false, error: "Invalid curve" };
}

// --------------------------------------------------------------------- base

// A dotfiles curve the generator leaves out (animationsgen.py check_base): a
// name that is not a Lua identifier cannot be written, and Hyprland skips a
// curve without a known type.
function isIgnoredBaseCurve(base, name) {
    if (!IDENT_RE.test(name))
        return true;
    var curves = base && base.curves ? base.curves : {};
    if (!Object.prototype.hasOwnProperty.call(curves, name))
        return false;
    var desc = curves[name];
    return !desc || (desc.type !== "bezier" && desc.type !== "spring");
}

// `enabled` of a base animation: Hyprland reads 0 / 1 as false / true and
// rejects other numbers (null: the line is ignored).
function baseEnabled(item) {
    if (isNumber(item.enabled))
        return item.enabled === 0 ? false : (item.enabled === 1 ? true : null);
    return item.enabled !== false;
}

// Effective tuple of a leaf in the dotfiles base (hyprbase.py "animations"):
// the nearest overridden ancestor, else Hyprland's compiled default. A base
// line Hyprland rejects is skipped as animationsgen.py check_base skips it:
// enabled without a speed, a numeric `enabled` other than 0 or 1, or an
// ignored curve (tests/fixtures/animation-cases.json "bases").
function resolveLeaf(base, leaf) {
    var animations = base && base.animations ? base.animations : {};
    for (var node = leaf; node; node = PARENTS[node]) {
        var item = animations[node];
        if (item) {
            var enabled = baseEnabled(item);
            if (enabled === false && !("speed" in item))
                return { enabled: false, speed: 1, curve: "default", style: "" };
            var curve = item.bezier !== undefined ? item.bezier : (item.spring !== undefined ? item.spring : "default");
            var skipped = enabled === null || !isNumber(item.speed) || (typeof curve === "string" && isIgnoredBaseCurve(base, curve));
            if (!skipped) {
                return {
                    enabled: enabled,
                    speed: item.speed,
                    curve: curve,
                    style: item.style || ""
                };
            }
        }
        if (COMPILED[node])
            return plain(COMPILED[node]);
    }
    return plain(COMPILED.global);
}

// Base value of a card, or undefined when the base is unknown.
function baseCard(cardId, base) {
    var c = card(cardId);
    if (!c || !base)
        return undefined;
    return resolveLeaf(base, c.leaf);
}

function compiledCard(cardId) {
    var c = card(cardId);
    return c ? resolveLeaf(null, c.leaf) : undefined;
}

// Value shown for a card: managed (generated file) -> base -> compiled default.
function cardValue(cardId, managed, base) {
    if (managed && managed[cardId])
        return plain(managed[cardId]);
    return base ? baseCard(cardId, base) : compiledCard(cardId);
}

// Contracts §1: the fade companion follows the primary's enabled state and
// scales its base speed by primary / base primary; with a spring it keeps its
// base speed (springs ignore speed). Curve and style keep the base.
function companionValue(cardId, primary, base, catalog) {
    var c = card(cardId);
    if (!c || !c.companion)
        return null;
    var baseP = resolveLeaf(base, c.leaf);
    var baseC = resolveLeaf(base, c.companion);
    var speed;
    if (isSpring(catalog, primary.curve) || !(baseP.speed > 0))
        speed = baseC.speed;
    else
        speed = Math.min(100, Math.max(0.01, round2(baseC.speed * primary.speed / baseP.speed)));
    return { enabled: primary.enabled, speed: speed, curve: baseC.curve, style: "" };
}

// ------------------------------------------------------------------ presets

// { card: value } of a preset, or null for "default"/"custom" or without base.
function presetCards(preset, base) {
    var table = PRESETS[preset];
    if (!table || !base)
        return null;
    var out = {};
    for (var i = 0; i < CARDS.length; i++) {
        var id = CARDS[i].id;
        out[id] = Object.assign(baseCard(id, base), table[id] || {});
    }
    return out;
}

// Preset matching the shown cards: "default" when every card shows its base
// value (or nothing is managed), the first preset whose 10 tuples all match,
// otherwise "custom".
function presetFor(managed, base) {
    var count = Object.keys(managed || {}).filter(function (k) { return CARD_IDS.indexOf(k) >= 0; }).length;
    if (count === 0)
        return "default";
    if (!base)
        return "custom";
    var shown = {};
    var allBase = true;
    for (var i = 0; i < CARDS.length; i++) {
        var id = CARDS[i].id;
        shown[id] = cardValue(id, managed, base);
        if (!equal(shown[id], baseCard(id, base)))
            allBase = false;
    }
    if (allBase)
        return "default";
    for (var p = 1; p < PRESET_IDS.length; p++) {
        var cards = presetCards(PRESET_IDS[p], base);
        if (CARD_IDS.every(function (id) { return equal(shown[id], cards[id]); }))
            return PRESET_IDS[p];
    }
    return "custom";
}

// [{ value, label, description }] for the preset control ("custom" is read only).
function presets() {
    return PRESET_IDS.map(function (id) {
        return { value: id, label: PRESET_LABELS[id], description: PRESET_DESCRIPTIONS[id] };
    });
}

// Card ids whose shown value uses the curve.
function curveUsage(name, managed, base) {
    return CARD_IDS.filter(function (id) {
        var v = cardValue(id, managed, base);
        return !!v && v.curve === name;
    });
}

// ------------------------------------------------------------------ summary

// Parts of a collapsed card's summary; the page translates and joins them.
// { enabled, style: { kind, label, percent, direction, known, raw } | null,
//   durationMs (null for springs, whose timing ignores speed), spring,
//   curve: { name, label, known } }.
function summaryParts(cardId, value, catalog) {
    if (!value)
        return null;
    var family = familyOf(cardId);
    var style = null;
    if (family !== "none") {
        var parsed = parseStyle(cardId, value.style);
        var label = parsed.known ? STYLE_LABELS[parsed.kind] : "Not recognized: %1";
        var percent = parsed.percent;
        // popin 100% grows from full size: only the fade is visible.
        if (parsed.known && parsed.kind === "popin" && parsed.percent === 100) {
            label = "Fade only";
            percent = null;
        }
        style = { kind: parsed.kind, label: label, percent: percent, direction: parsed.direction, known: parsed.known, raw: parsed.raw };
    }
    var curve = findCurve(catalog, value.curve);
    var spring = !!curve && curve.type === "spring";
    return {
        enabled: !!value.enabled,
        style: style,
        durationMs: spring ? null : durationMs(value.speed),
        spring: spring,
        curve: { name: value.curve, label: curve ? curve.label : "Not recognized: %1", known: !!curve }
    };
}

// -------------------------------------------------------- loaded confirmation

// Cards whose primary leaf in `hyprctl -j animations` ([animations, beziers])
// does not show the written tuple: Hyprland did not load the generated file.
// Speeds are compared at hyprctl's 2-decimal precision.
function loadedMismatches(text, managed, catalog) {
    var list = animationList(text);
    if (!list)
        return Object.keys(managed || {});
    var byName = {};
    list.forEach(function (item) { if (item && typeof item.name === "string") byName[item.name] = item; });
    return Object.keys(managed || {}).filter(function (id) {
        var c = card(id);
        if (!c)
            return false;
        var want = managed[id];
        var got = byName[c.leaf];
        if (!got || got.overridden !== true || !!got.enabled !== !!want.enabled)
            return true;
        if (!want.enabled)
            return false;
        var bezier = isSpring(catalog, want.curve) ? "spring:" + want.curve : want.curve;
        return Math.abs(Number(got.speed) - round2(want.speed)) > 0.006 || got.bezier !== bezier
            || String(got.style || "") !== want.style;
    });
}

// The animation list of `hyprctl -j animations` ([animations, beziers]), or
// null when the text is not that shape (a failed or cut-off read).
function animationList(text) {
    try {
        var parsed = JSON.parse(String(text || ""));
        return Array.isArray(parsed) && Array.isArray(parsed[0]) ? parsed[0] : null;
    } catch (error) {
        return null;
    }
}

// Lua source without its comments (`-- line` and `--[==[ block ]==]`).
// Strings are kept as they are, so a "--" inside one is not a comment.
function stripLuaComments(text) {
    text = String(text || "");
    var out = "";
    var i = 0;
    var n = text.length;
    // Level of a long bracket `[==[` starting at `at`, or -1.
    function longLevel(at) {
        if (text[at] !== "[")
            return -1;
        var k = at + 1;
        while (text[k] === "=")
            k++;
        return text[k] === "[" ? k - at - 1 : -1;
    }
    while (i < n) {
        var c = text[i];
        if (c === "-" && text[i + 1] === "-") {
            var level = longLevel(i + 2);
            if (level >= 0) {
                var close = "]" + "=".repeat(level) + "]";
                var end = text.indexOf(close, i + 4 + level);
                i = end < 0 ? n : end + close.length;
                out += " ";
            } else {
                var eol = text.indexOf("\n", i);
                i = eol < 0 ? n : eol;
            }
            continue;
        }
        if (c === "\"" || c === "'") {
            var j = i + 1;
            while (j < n && text[j] !== c && text[j] !== "\n")
                j += text[j] === "\\" ? 2 : 1;
            out += text.slice(i, j + 1);
            i = j + 1;
            continue;
        }
        var strLevel = longLevel(i);
        if (strLevel >= 0) {
            var strClose = "]" + "=".repeat(strLevel) + "]";
            var strEnd = text.indexOf(strClose, i + 2 + strLevel);
            var stop = strEnd < 0 ? n : strEnd + strClose.length;
            out += text.slice(i, stop);
            i = stop;
            continue;
        }
        out += c;
        i++;
    }
    return out;
}

// True when hyprland.lua requires custom.shell-animations outside a comment.
function requiresAnimations(text) {
    return /\brequire\b[^\n]*["']custom\.shell-animations["']/.test(stripLuaComments(text));
}
