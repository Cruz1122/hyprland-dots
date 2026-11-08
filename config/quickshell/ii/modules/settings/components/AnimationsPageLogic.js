.pragma library
.import "../backends/AnimationLogic.js" as AL

// Pure helpers of the Animations page widgets (SettingsAnimationRow,
// SettingsAnimationPresetRow, SettingsCurveLibraryRow; docs/settings.md
// "Animations page"). No QML objects, so tests/qml_settings exercises them.
// Texts are English source strings; callers pass `tr` (Translation.tr) so the
// result is already translated.

var MIN_MS = 50;
var MAX_MS = 2000;
var STEP_MS = 10;
var USER_CURVE_PREFIX = "ii_curve_";
var DIRECTION_FORMATS = {
    top: "%1 from the top",
    bottom: "%1 from the bottom",
    left: "%1 from the left",
    right: "%1 from the right"
};

function arg(text, value) {
    return String(text).replace("%1", String(value));
}

function arg2(text, a, b) {
    return String(text).replace("%1", String(a)).replace("%2", String(b));
}

// A spring's duration as the card shows it: Hyprland's settle time rounded
// to 10 ms (CurveMath.springSettleMs gives the exact value).
function roundedSettleMs(ms) {
    return Math.round(Number(ms) / 10) * 10;
}

// Duration slider position for a Hyprland speed: ms clamped to the UI range.
function sliderMs(speed) {
    var ms = Math.round(Number(speed) * 100);
    if (!isFinite(ms))
        return MIN_MS;
    return Math.max(MIN_MS, Math.min(MAX_MS, ms));
}

function findCurve(catalog, name) {
    for (var i = 0; i < (catalog || []).length; i++) {
        if (catalog[i] && catalog[i].name === name)
            return catalog[i];
    }
    return null;
}

// Label of a curve descriptor: user curves show what the user typed, the
// others are English source strings.
function curveLabel(curve, tr) {
    if (!curve)
        return "";
    var label = String(curve.label || curve.name || "");
    return curve.group === "user" ? label : tr(label);
}

// The style part of a summary: "Pop in 80%", "Slide from the left",
// "Fade only", "Not recognized: X"; "" for cards without a style.
function styleText(style, tr) {
    if (!style)
        return "";
    if (!style.known)
        return arg(tr("Not recognized: %1"), style.raw);
    var label = tr(style.label);
    if (style.percent !== null && style.percent !== undefined)
        return arg2(tr("%1 %2%"), label, style.percent);
    if (style.direction && DIRECTION_FORMATS[style.direction])
        return arg(tr(DIRECTION_FORMATS[style.direction]), label);
    return label;
}

// Folded card summary from AnimationBackend.summaryParts(card):
// "Pop in 80% · 300 ms · Quick start, gentle stop". `springMs` is the
// spring's settle time (CurveMath.springSettleMs) when the curve is a spring.
function summaryText(parts, catalog, tr, springMs) {
    if (!parts)
        return "";
    if (!parts.enabled)
        return tr("No animation");
    var out = [];
    var style = styleText(parts.style, tr);
    if (style.length > 0)
        out.push(style);
    if (parts.spring)
        out.push(arg(tr("≈ %1 ms (set by the spring)"), roundedSettleMs(springMs)));
    else if (parts.durationMs !== null && parts.durationMs !== undefined)
        out.push(arg(tr("%1 ms"), Math.round(parts.durationMs)));
    if (parts.curve) {
        if (parts.curve.known)
            out.push(curveLabel(findCurve(catalog, parts.curve.name) || parts.curve, tr));
        else
            out.push(arg(tr("Not recognized: %1"), parts.curve.name));
    }
    return out.join(" · ");
}

// Style kinds offered for a card: AnimationBackend.styleOptions(card) plus
// "none" (Hyprland's default) only while the card uses it, so the control
// always shows the current value. [] for cards without a style.
function styleChoices(options, parsed) {
    var out = (options || []).map(function (o) {
        return { kind: o.kind, label: o.label, description: o.description || "", percent: !!o.percent, directions: o.directions || [] };
    });
    if (out.length > 0 && parsed && parsed.known && parsed.kind === "none")
        out.unshift({ kind: "none", label: "Hyprland default", description: "", percent: false, directions: [] });
    return out;
}

// Style text after changing one part of the parsed style. Changing the kind
// keeps a percent or side the new kind accepts; a percent kind without one
// starts at `defaultPercent`.
function restyle(cardId, parsed, change, choices, defaultPercent) {
    var next = { kind: parsed.kind, percent: parsed.percent, direction: parsed.direction, known: true };
    if (change.kind !== undefined)
        next.kind = change.kind;
    if (change.percent !== undefined)
        next.percent = change.percent;
    if (change.direction !== undefined)
        next.direction = change.direction;
    var choice = null;
    for (var i = 0; i < (choices || []).length; i++) {
        if (choices[i].kind === next.kind)
            choice = choices[i];
    }
    if (!choice || !choice.percent)
        next.percent = null;
    else if (next.percent === null || next.percent === undefined)
        next.percent = defaultPercent === undefined ? 80 : defaultPercent;
    if (!choice || (choice.directions || []).indexOf(next.direction) < 0)
        next.direction = "";
    return AL.formatStyle(cardId, next);
}

// Card value with one field changed (the backend validates the result).
function withField(value, field, fieldValue) {
    var out = { enabled: !!value.enabled, speed: value.speed, curve: value.curve, style: value.style };
    out[field] = fieldValue;
    return out;
}

// Preset choices for the row: the five presets, plus a read-only "custom"
// one while the cards match none of them.
function presetChoices(presets, current) {
    var out = (presets || []).map(function (p) {
        return { value: p.value, label: p.label, description: p.description || "", readOnly: false };
    });
    if (current === "custom")
        out.push({ value: "custom", label: "Custom", description: "Your own mix: the animation cards match none of the presets.", readOnly: true });
    return out;
}

// Undo of a preset: [{ key, action: "write" | "reset", value }] from the
// cards captured before it, [{ key, managed, value }]: cards that were in
// the generated file get their value back, the others lose their line.
function undoPlan(snapshot) {
    return (snapshot || []).map(function (item) {
        return item.managed ? { key: item.key, action: "write", value: item.value } : { key: item.key, action: "reset" };
    });
}

// A free curve name for a new user curve (the backend accepts
// ^ii_[a-z0-9_]{1,32}$); the user only ever sees the label.
function newCurveName(names) {
    var taken = {};
    (names || []).forEach(function (n) { taken[n] = true; });
    for (var i = 1; i < 100000; i++) {
        var name = USER_CURVE_PREFIX + i;
        if (!taken[name])
            return name;
    }
    return "";
}

// Problem with a typed curve label, as an English source string, or ""
// (the backend's own rule, AnimationLogic.labelProblem).
function labelProblem(label) {
    return AL.labelProblem(label);
}

// The user's curve list with one curve replaced, added (name not present)
// or removed (desc null), as the value for animation.curves.
function curvesWith(list, name, desc) {
    var out = [];
    var found = false;
    (list || []).forEach(function (c) {
        if (c.name !== name) {
            out.push(storedCurve(c));
            return;
        }
        found = true;
        if (desc)
            out.push(storedCurve(Object.assign({}, desc, { name: name })));
    });
    if (!found && desc)
        out.push(storedCurve(Object.assign({}, desc, { name: name })));
    return out;
}

// Only the fields a user curve stores.
function storedCurve(c) {
    var out = { name: c.name, type: c.type, label: c.label };
    if (c.type === "spring") {
        out.mass = c.mass;
        out.stiffness = c.stiffness;
        out.damping = c.damping;
    } else {
        out.points = (c.points || []).slice();
    }
    return out;
}
