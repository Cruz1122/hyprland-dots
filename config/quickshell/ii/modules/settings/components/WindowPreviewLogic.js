.pragma library

// Pure geometry of SettingsWindowPreview.qml (tests/qml_settings/tst_SettingsWindowPreview.qml).
//
// The mini desktop is a virtual 1280×800 screen drawn at `scale`, with the
// bar's reserved strip on top and Hyprland's dwindle layout of three tiled
// windows (one on the left, two stacked on the right) plus a floating window.
// Each tiled window's box keeps gaps_out from the work area's edges and
// gaps_in from the split lines, so two neighbors are 2 × gaps_in apart. The
// border is drawn outside the window's content, inside that box: the live
// session places a window at gaps_out + border_size from the edge
// (`hyprctl -j clients`, gaps_out 5, border 1: x = 6).

var SCREEN_WIDTH = 1280;
var SCREEN_HEIGHT = 800;
// The bar's reserved strip (`hyprctl -j monitors`: reserved [0, 40, 0, 0]).
var BAR_HEIGHT = 40;

// Example values for when Hyprland is not running (the dotfiles' own values).
var EXAMPLE = {
    gapsIn: 4, gapsOut: 5, border: 1, rounding: 18, roundingPower: 2.5,
    blur: true, blurSize: 10, blurPasses: 3,
    shadow: true, shadowRange: 20, shadowPower: 4,
    dim: true, dimStrength: 0.05,
    activeOpacity: 1, inactiveOpacity: 1
};

// Registry key -> the part of the preview it changes.
var KEY_PARTS = {
    "hyprland.general.gaps_in": "gapsIn",
    "hyprland.general.gaps_out": "gapsOut",
    "hyprland.general.border_size": "border",
    "hyprland.decoration.rounding": "rounding",
    "hyprland.decoration.rounding_power": "roundingPower",
    "hyprland.decoration.blur.enabled": "blur",
    "hyprland.decoration.blur.size": "blur",
    "hyprland.decoration.blur.passes": "blur",
    "hyprland.decoration.blur.xray": "blur",
    "hyprland.decoration.shadow.enabled": "shadow",
    "hyprland.decoration.shadow.range": "shadow",
    "hyprland.decoration.shadow.render_power": "shadow",
    "hyprland.decoration.dim_inactive": "dim",
    "hyprland.decoration.dim_strength": "dim",
    "hyprland.decoration.active_opacity": "activeOpacity",
    "hyprland.decoration.inactive_opacity": "inactiveOpacity"
};

// Store key of each value the preview reads.
var VALUE_KEYS = {
    gapsIn: "hyprland.general.gaps_in",
    gapsOut: "hyprland.general.gaps_out",
    border: "hyprland.general.border_size",
    rounding: "hyprland.decoration.rounding",
    roundingPower: "hyprland.decoration.rounding_power",
    blur: "hyprland.decoration.blur.enabled",
    blurSize: "hyprland.decoration.blur.size",
    blurPasses: "hyprland.decoration.blur.passes",
    shadow: "hyprland.decoration.shadow.enabled",
    shadowRange: "hyprland.decoration.shadow.range",
    shadowPower: "hyprland.decoration.shadow.render_power",
    dim: "hyprland.decoration.dim_inactive",
    dimStrength: "hyprland.decoration.dim_strength",
    activeOpacity: "hyprland.decoration.active_opacity",
    inactiveOpacity: "hyprland.decoration.inactive_opacity"
};

function partForKey(key) {
    return Object.prototype.hasOwnProperty.call(KEY_PARTS, key) ? KEY_PARTS[key] : "";
}

function _num(value, fallback, min, max) {
    var n = Number(value);
    if (value === undefined || value === null || value === "" || typeof value === "boolean" || !isFinite(n))
        n = fallback;
    return Math.min(max, Math.max(min, n));
}

// Raw store values ({ gapsIn: …, … }, undefined when unknown) -> a complete,
// clamped set. `known` is false when any value was missing, so the preview
// says it shows example values.
function normalize(raw) {
    var r = raw || {};
    var known = true;
    for (var name in EXAMPLE) {
        if (r[name] === undefined || r[name] === null)
            known = false;
    }
    function bool(name) {
        return typeof r[name] === "boolean" ? r[name] : EXAMPLE[name];
    }
    return {
        known: known,
        gapsIn: Math.round(_num(r.gapsIn, EXAMPLE.gapsIn, 0, 200)),
        gapsOut: Math.round(_num(r.gapsOut, EXAMPLE.gapsOut, 0, 200)),
        border: Math.round(_num(r.border, EXAMPLE.border, 0, 40)),
        rounding: Math.round(_num(r.rounding, EXAMPLE.rounding, 0, 200)),
        roundingPower: _num(r.roundingPower, EXAMPLE.roundingPower, 1, 10),
        blur: bool("blur"),
        blurSize: _num(r.blurSize, EXAMPLE.blurSize, 0, 100),
        blurPasses: Math.round(_num(r.blurPasses, EXAMPLE.blurPasses, 0, 10)),
        shadow: bool("shadow"),
        shadowRange: _num(r.shadowRange, EXAMPLE.shadowRange, 0, 300),
        shadowPower: _num(r.shadowPower, EXAMPLE.shadowPower, 1, 4),
        dim: bool("dim"),
        dimStrength: _num(r.dimStrength, EXAMPLE.dimStrength, 0, 1),
        activeOpacity: _num(r.activeOpacity, EXAMPLE.activeOpacity, 0, 1),
        inactiveOpacity: _num(r.inactiveOpacity, EXAMPLE.inactiveOpacity, 0, 1)
    };
}

function _box(x, y, w, h) {
    return { x: x, y: y, width: Math.max(0, w), height: Math.max(0, h) };
}

// Rounding never exceeds half the shorter side (Hyprland clamps it too).
function _radius(r, box) {
    return Math.max(0, Math.min(r, box.width / 2, box.height / 2));
}

// The three tiled windows in screen pixels (unscaled), plus the gaps between
// them, for values `v` from normalize(). Each window: { id, active, box
// (outer, with the border), content (inside the border), radius (content),
// outerRadius }.
function tiledWindows(v) {
    var top = BAR_HEIGHT + v.gapsOut;
    var left = v.gapsOut;
    var right = SCREEN_WIDTH - v.gapsOut;
    var bottom = SCREEN_HEIGHT - v.gapsOut;
    var splitX = SCREEN_WIDTH / 2;
    var splitY = BAR_HEIGHT + (SCREEN_HEIGHT - BAR_HEIGHT) / 2;
    var boxes = [
        { id: "main", active: true, box: _box(left, top, splitX - v.gapsIn - left, bottom - top) },
        { id: "topRight", active: false, box: _box(splitX + v.gapsIn, top, right - splitX - v.gapsIn, splitY - v.gapsIn - top) },
        { id: "bottomRight", active: false, box: _box(splitX + v.gapsIn, splitY + v.gapsIn, right - splitX - v.gapsIn, bottom - splitY - v.gapsIn) }
    ];
    return boxes.map(function (w) {
        var b = Math.min(v.border, w.box.width / 2, w.box.height / 2);
        w.content = _box(w.box.x + b, w.box.y + b, w.box.width - 2 * b, w.box.height - 2 * b);
        w.border = b;
        w.radius = _radius(v.rounding, w.content);
        w.outerRadius = w.radius > 0 ? w.radius + b : 0;
        return w;
    });
}

// Floating window over the bottom-right tile, with its shadow reach.
function floatingWindow(v) {
    var content = _box(700, 470, 400, 250);
    var b = v.border;
    var r = _radius(v.rounding, content);
    return {
        id: "floating", active: false,
        content: content,
        box: _box(content.x - b, content.y - b, content.width + 2 * b, content.height + 2 * b),
        border: b, radius: r, outerRadius: r > 0 ? r + b : 0,
        shadowRange: v.shadow ? v.shadowRange : 0
    };
}

// A shell panel (a notification popup) in the top-right corner, below the bar.
function panelBox(v) {
    return _box(SCREEN_WIDTH - 12 - 300, BAR_HEIGHT + 8, 300, 150);
}

function barBox() {
    return _box(0, 0, SCREEN_WIDTH, BAR_HEIGHT);
}

// How soft the blur looks, in screen pixels: Hyprland's Kawase blur spreads
// further with each pass. Approximate; 0 when blur is off.
function blurRadius(v) {
    if (!v.blur)
        return 0;
    return Math.min(160, v.blurSize * Math.max(1, v.blurPasses) * 1.5);
}

// Canvas shadowBlur for the floating window: the range is the reach; a
// higher render power makes the edge sharper and shorter.
function shadowBlur(v) {
    if (!v.shadow)
        return 0;
    return v.shadowRange * (1.25 - 0.2 * (v.shadowPower - 1));
}

// The preview darkens inactive windows more than Hyprland does so that small
// strengths are visible (the preview says so): ×3, at most 0.75.
function shownDim(v) {
    if (!v.dim)
        return 0;
    return Math.min(0.75, v.dimStrength * 3);
}

// Points of a rectangle whose corners are superellipses |x|^p + |y|^p = r^p
// (p = rounding_power; 2 is a quarter circle), clockwise from the top edge.
// `steps` points per corner.
function roundedRectPoints(box, r, p, steps) {
    var n = Math.max(2, Math.round(steps || 12));
    var radius = _radius(r, box);
    var power = Math.max(1, Number(p) || 2);
    if (radius <= 0)
        return [
            { x: box.x, y: box.y }, { x: box.x + box.width, y: box.y },
            { x: box.x + box.width, y: box.y + box.height }, { x: box.x, y: box.y + box.height }
        ];
    // Corner centres, clockwise from the top-right one (screen y points down).
    var centres = [
        { x: box.x + box.width - radius, y: box.y + radius },
        { x: box.x + box.width - radius, y: box.y + box.height - radius },
        { x: box.x + radius, y: box.y + box.height - radius },
        { x: box.x + radius, y: box.y + radius }
    ];
    var points = [];
    for (var c = 0; c < 4; c++) {
        for (var i = 0; i <= n; i++) {
            // θ from −π/2 (top-right corner, top tangent) a quarter turn per corner.
            var theta = -Math.PI / 2 + (c + i / n) * Math.PI / 2;
            var cos = Math.cos(theta);
            var sin = Math.sin(theta);
            points.push({
                x: centres[c].x + radius * (cos < 0 ? -1 : 1) * Math.pow(Math.abs(cos), 2 / power),
                y: centres[c].y + radius * (sin < 0 ? -1 : 1) * Math.pow(Math.abs(sin), 2 / power)
            });
        }
    }
    return points;
}

// Distance from a corner of the box to the curve along the diagonal, as a
// fraction of the radius: 1 − 2^(−1/p). A circle (p = 2) gives ≈ 0.29;
// higher powers hug the corner (smaller values).
function cornerInset(p) {
    var power = Math.max(1, Number(p) || 2);
    return 1 - Math.pow(2, -1 / power);
}

function _scaleBox(b, s) {
    return { x: b.x * s, y: b.y * s, width: b.width * s, height: b.height * s };
}

// Everything the mini desktop draws, scaled to `width` pixels. A border
// thinner than one pixel after scaling is drawn 1 px wide so it stays
// visible.
function desktop(values, width) {
    var v = normalize(values);
    var s = Math.max(0.05, Number(width) || 0) / SCREEN_WIDTH;
    function scaleWindow(w) {
        var out = {};
        for (var k in w)
            out[k] = w[k];
        out.box = _scaleBox(w.box, s);
        out.border = w.border > 0 ? Math.min(Math.max(1, w.border * s), out.box.width / 2, out.box.height / 2) : 0;
        out.content = _box(out.box.x + out.border, out.box.y + out.border,
            out.box.width - 2 * out.border, out.box.height - 2 * out.border);
        out.radius = w.radius * s;
        out.outerRadius = w.outerRadius > 0 ? w.radius * s + out.border : 0;
        if (w.shadowRange !== undefined)
            out.shadowRange = w.shadowRange * s;
        return out;
    }
    return {
        values: v,
        scale: s,
        width: SCREEN_WIDTH * s,
        height: SCREEN_HEIGHT * s,
        bar: _scaleBox(barBox(), s),
        panel: _scaleBox(panelBox(v), s),
        tiled: tiledWindows(v).map(scaleWindow),
        floating: scaleWindow(floatingWindow(v)),
        blurRadius: blurRadius(v) * s,
        shadowBlur: shadowBlur(v) * s,
        dim: shownDim(v)
    };
}

// The 1:1 magnifier: a `width`×`height` crop around the top-right corner of
// the main window, at real size. The corner sits at (anchorX, anchorY) of
// the crop, so the screen edge (gaps_out) is above it and the neighbor
// (2 × gaps_in away) to its right. Boxes are in crop pixels.
function magnifier(values, width, height, anchorX, anchorY) {
    var v = normalize(values);
    var tiles = tiledWindows(v);
    var main = tiles[0];
    var cornerX = main.box.x + main.box.width;
    var cornerY = main.box.y;
    var dx = anchorX - cornerX;
    var dy = anchorY - cornerY;
    function shift(w) {
        var out = {};
        for (var k in w)
            out[k] = w[k];
        out.box = _box(w.box.x + dx, w.box.y + dy, w.box.width, w.box.height);
        out.content = _box(w.content.x + dx, w.content.y + dy, w.content.width, w.content.height);
        return out;
    }
    var shiftedBar = barBox();
    return {
        values: v,
        width: width,
        height: height,
        main: shift(main),
        neighbor: shift(tiles[1]),
        bar: _box(shiftedBar.x + dx, shiftedBar.y + dy, shiftedBar.width, shiftedBar.height),
        // Measured spans, in crop pixels: [from, to] along one axis.
        edgeGap: { x: anchorX - 28, y1: anchorY - v.gapsOut, y2: anchorY, size: v.gapsOut },
        innerGap: { y: anchorY + 34, x1: anchorX, x2: anchorX + 2 * v.gapsIn, size: v.gapsIn },
        border: { size: main.border },
        rounding: { size: main.radius, power: v.roundingPower }
    };
}

// `hyprctl -j getoption general:col.active_border` -> "#AARRGGBB" of its
// first colour, or "" when the answer has none. Hyprland prints gradients as
// "AARRGGBB[ AARRGGBB…] <angle>deg" (the stub prints the same under "str").
function borderColor(text) {
    var data;
    try {
        data = JSON.parse(String(text));
    } catch (error) {
        return "";
    }
    if (!data || typeof data !== "object")
        return "";
    var raw = data.gradient !== undefined ? data.gradient : data.str !== undefined ? data.str : data.color;
    var match = /^\s*(?:0x)?([0-9a-fA-F]{8})\b/.exec(String(raw === undefined ? "" : raw));
    return match ? "#" + match[1].toLowerCase() : "";
}
