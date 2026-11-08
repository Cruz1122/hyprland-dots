.pragma library

// Curve semantics of Hyprland animations, as pure functions (no QML, no
// state besides small caches). Ported from hyprutils v0.14.3, the version
// Hyprland 0.57 links against:
//   src/animation/BezierCurve.cpp     -> bake(), bezierY()
//   src/animation/Spring.cpp          -> advanceSpring()
//   src/animation/AnimatedVariable.cpp (getCurveStep, getPercent)
//                                     -> springProgress(), springSettleMs()
// hyprutils computes in 32-bit floats; this port uses doubles. The
// difference is below 1e-6 for every curve the app offers, and both this
// file and the independent Python port (tests/curve_reference.py) use doubles
// with the same operation order, so the golden fixture
// (tests/fixtures/curve-golden.json) pins them to each other.
//
// Curve descriptors: { name, type: "bezier", points: [x1, y1, x2, y2] } or
// { name, type: "spring", mass, stiffness, damping }.

// hyprutils BAKEDPOINTS: the curve is baked at t = 1/255 .. 255/255 (t = 0
// is not baked, so the first baked x can be above 0).
var BAKED_POINTS = 255;

// Hyprland drives animations from a 1 ms event-loop timer
// (CHyprAnimationManager::scheduleTick / frameTick, ticks at most every 1 ms),
// not from the monitor refresh. advanceSpring() is the closed-form solution
// of the damped oscillator, so the spring position at time t does not depend
// on how the time was split into ticks (up to rounding); only the moment
// Hyprland declares the spring finished does, and springSettleMs() assumes
// 1 ms ticks for it.
var SPRING_TICK_MS = 1;
// Upper bound for springSettleMs(): a nearly undamped spring would otherwise
// loop for minutes.
var SPRING_MAX_MS = 10000;
// SSpringCurve::valueEpsilon / velocityEpsilon.
var SPRING_VALUE_EPSILON = 0.001;
var SPRING_VELOCITY_EPSILON = 0.001;

// Hyprland accepts control-point coordinates in [-1, 2]; the editor keeps x
// in [0, 1] so the timing stays monotonic.
var X_MIN = 0;
var X_MAX = 1;
var Y_MIN = -1;
var Y_MAX = 2;

// Hyprland's built-in curves: "default" (hyprutils) and "linear" (Hyprland).
var DEFAULT_POINTS = [0, 0.75, 0.15, 1];
var LINEAR_POINTS = [0, 0, 1, 1];

// Bounded caches: the editor creates a new point set on every drag step.
var CACHE_LIMIT = 64;
var _bakedCache = {};
var _bakedCount = 0;
var _settleCache = {};
var _settleCount = 0;

function _cubic(t, p0, p1, p2, p3) {
    var t2 = t * t;
    var t3 = t2 * t;
    return ((1 - t) * (1 - t) * (1 - t) * p0) + (3 * t * (1 - t) * (1 - t) * p1) + (3 * t2 * (1 - t) * p2) + (t3 * p3);
}

// CBezierCurve::setup + setup4: { xs, ys } of the 255 baked points of the
// curve (0,0) (x1,y1) (x2,y2) (1,1).
function bake(points) {
    var xs = new Array(BAKED_POINTS);
    var ys = new Array(BAKED_POINTS);
    for (var i = 0; i < BAKED_POINTS; ++i) {
        var t = (i + 1) * (1 / BAKED_POINTS);
        xs[i] = _cubic(t, 0, points[0], points[2], 1);
        ys[i] = _cubic(t, 0, points[1], points[3], 1);
    }
    return { xs: xs, ys: ys };
}

function _baked(points) {
    var key = points.join(",");
    var hit = _bakedCache[key];
    if (hit)
        return hit;
    if (_bakedCount >= CACHE_LIMIT) {
        _bakedCache = {};
        _bakedCount = 0;
    }
    hit = bake(points);
    _bakedCache[key] = hit;
    _bakedCount++;
    return hit;
}

// CBezierCurve::getYForPoint: binary search over the baked x values, then a
// linear interpolation between the two neighbouring baked points.
function bezierY(points, x) {
    if (x >= 1)
        return 1;
    if (x <= 0)
        return 0;
    var baked = _baked(points);
    var xs = baked.xs;
    var ys = baked.ys;

    var index = 0;
    var below = true;
    for (var step = Math.floor((BAKED_POINTS + 1) / 2); step > 0; step = Math.floor(step / 2)) {
        if (below)
            index += step;
        else
            index -= step;
        if (index < 0)
            index = 0;
        else if (index > BAKED_POINTS - 1)
            index = BAKED_POINTS - 1;
        below = xs[index] < x;
    }

    var lowerIndex = index - ((!below || index === BAKED_POINTS - 1) ? 1 : 0);
    if (lowerIndex < 0)
        lowerIndex = 0;
    else if (lowerIndex > BAKED_POINTS - 2)
        lowerIndex = BAKED_POINTS - 2;

    var dx = xs[lowerIndex + 1] - xs[lowerIndex];
    if (dx <= 1e-6)
        return ys[lowerIndex];
    var perc = (x - xs[lowerIndex]) / dx;
    if (!isFinite(perc))
        return ys[lowerIndex];
    return ys[lowerIndex] + ((ys[lowerIndex + 1] - ys[lowerIndex]) * perc);
}

// Animation::advanceSpring: moves { value, velocity } (target 1) forward by
// dtSeconds with the closed-form damped-oscillator solution.
function advanceSpring(value, velocity, spring, dtSeconds) {
    var dt = Math.max(dtSeconds, 0);
    if (dt <= 0)
        return { value: value, velocity: velocity };

    var mass = Math.max(spring.mass, 0.0001);
    var stiffness = Math.max(spring.stiffness, 0.0001);
    var damping = Math.max(spring.damping, 0);

    var displacement = value - 1;
    var omega0 = Math.sqrt(stiffness / mass);
    var gamma = damping / (2 * mass);

    if (gamma < omega0) {
        var omegaD = Math.sqrt((omega0 * omega0) - (gamma * gamma));
        var e = Math.exp(-gamma * dt);
        var s = Math.sin(omegaD * dt);
        var c = Math.cos(omegaD * dt);
        var newDisplacement = e * ((displacement * c) + (((velocity + (gamma * displacement)) / omegaD) * s));
        var newVelocity = e * ((velocity * c) - (((gamma * velocity) + (omega0 * omega0 * displacement)) / omegaD) * s);
        return { value: 1 + newDisplacement, velocity: newVelocity };
    }

    var criticalEpsilon = Math.max(omega0, 1) * 0.0001;
    if (Math.abs(gamma - omega0) <= criticalEpsilon) {
        var ec = Math.exp(-gamma * dt);
        var b = velocity + (gamma * displacement);
        return { value: 1 + (ec * (displacement + (b * dt))), velocity: ec * (velocity - (gamma * b * dt)) };
    }

    var root = Math.sqrt((gamma * gamma) - (omega0 * omega0));
    var r1 = -gamma + root;
    var r2 = -gamma - root;
    var a = (velocity - (r2 * displacement)) / (r1 - r2);
    var bb = displacement - a;
    var e1 = Math.exp(r1 * dt);
    var e2 = Math.exp(r2 * dt);
    return { value: 1 + (a * e1) + (bb * e2), velocity: (a * r1 * e1) + (bb * r2 * e2) };
}

function _springKey(spring) {
    return spring.mass + "," + spring.stiffness + "," + spring.damping;
}

// Milliseconds until Hyprland ends a spring animation started at rest:
// the first 1 ms tick where |1 - value| <= 0.001 and |velocity| <= 0.001
// (getCurveStep). Capped at SPRING_MAX_MS.
function springSettleMs(spring) {
    var key = _springKey(spring);
    if (_settleCache[key] !== undefined)
        return _settleCache[key];
    var state = { value: 0, velocity: 0 };
    var t = 0;
    while (t < SPRING_MAX_MS) {
        state = advanceSpring(state.value, state.velocity, spring, SPRING_TICK_MS / 1000);
        t += SPRING_TICK_MS;
        if (Math.abs(1 - state.value) <= SPRING_VALUE_EPSILON && Math.abs(state.velocity) <= SPRING_VELOCITY_EPSILON)
            break;
    }
    if (_settleCount >= CACHE_LIMIT) {
        _settleCache = {};
        _settleCount = 0;
    }
    _settleCache[key] = t;
    _settleCount++;
    return t;
}

// Spring position tMs after an animation starts at rest (value 0, velocity
// 0); exactly 1 from the tick Hyprland declares it finished.
function springProgress(spring, tMs) {
    if (!(tMs > 0))
        return 0;
    if (tMs >= springSettleMs(spring))
        return 1;
    return advanceSpring(0, 0, spring, tMs / 1000).value;
}

function isSpring(curve) {
    return curve?.type === "spring";
}

// Animated value for a linear progress in [0, 1] of an animation lasting
// durationMs (bezier: progress = elapsed / speedToMs(speed); spring: the
// time is progress * durationMs).
function valueAt(curve, linearProgress, durationMs) {
    if (isSpring(curve))
        return springProgress(curve, linearProgress * durationMs);
    var points = curve?.points ?? LINEAR_POINTS;
    return bezierY(points, linearProgress);
}

// Real length of an animation: a spring ignores Hyprland's speed.
function durationMs(curve, speed) {
    return isSpring(curve) ? springSettleMs(curve) : speedToMs(speed);
}

// n evenly spaced { x, y } samples (x in [0, 1]) of the timing function, for
// thumbnails; a spring's x spans its settle time.
function sample(curve, n) {
    var count = Math.max(2, Math.floor(n));
    var settle = isSpring(curve) ? springSettleMs(curve) : 1;
    var out = [];
    for (var i = 0; i < count; ++i) {
        var x = i / (count - 1);
        out.push({ x: x, y: valueAt(curve, x, settle) });
    }
    return out;
}

// Hyprland's speed is in deciseconds: progress = (elapsed_ms / 100) / speed.
function speedToMs(speed) {
    return speed * 100;
}

// Inverse of speedToMs, rounded to the 2 decimals `hyprctl -j` reports.
function msToSpeed(ms) {
    return Math.round(ms) / 100;
}

function _clamp(value, low, high) {
    var v = Number(value);
    if (!isFinite(v))
        return low;
    return Math.min(high, Math.max(low, v));
}

function clampX(x) {
    return _clamp(x, X_MIN, X_MAX);
}

function clampY(y) {
    return _clamp(y, Y_MIN, Y_MAX);
}

// [x1, y1, x2, y2] with x in [0, 1] and y in [-1, 2] (non-numbers become the
// lower bound).
function clampPoint(points) {
    return [clampX(points[0]), clampY(points[1]), clampX(points[2]), clampY(points[3])];
}
