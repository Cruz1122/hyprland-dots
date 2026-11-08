.pragma library

// Pure helpers behind "Speed of menus and transitions" and "Reduce motion in
// the shell" (appearance.animations.durationScale / reduceMotion). Appearance
// applies them to its motion presets; nothing here touches Hyprland.
//
// The factor multiplies durations (0.5 = twice as fast). reduceMotion makes it
// 0, but a scaled duration never drops below 1 ms: a 0 ms Qt animation can emit
// `finished` inside start(), which would run onFinished handlers (notification
// discard, panel close) re-entrantly in their caller. 1 ms ends on the next
// animation tick instead.

var MIN_SCALE = 0.25;
var MAX_SCALE = 3;
// SmoothedAnimation velocity used when motion is reduced: large enough to
// reach any target in one frame.
var INSTANT_VELOCITY = 1e6;

function factor(scale, reduce) {
    if (reduce === true)
        return 0;
    const value = Number(scale);
    // A missing or malformed value (string, null, NaN) keeps the normal speed.
    if (scale === null || scale === undefined || scale === "" || !isFinite(value))
        return 1;
    return Math.min(MAX_SCALE, Math.max(MIN_SCALE, value));
}

function duration(ms, f) {
    // 0 means "no animation" and -1 (or infinite) has its own Qt meaning:
    // leave them untouched.
    if (!(ms > 0) || !isFinite(ms))
        return ms;
    return Math.max(1, Math.round(ms * f));
}

function velocity(v, f) {
    if (!(f > 0))
        return INSTANT_VELOCITY;
    return v / f;
}

// Timer intervals tied to an animation follow the same rule as durations, so
// the timer still fires after (never before) the animation it waits for.
function interval(ms, f) {
    return duration(ms, f);
}
