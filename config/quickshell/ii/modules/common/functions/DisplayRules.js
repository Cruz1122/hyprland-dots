.pragma library

// Pure Hyprland monitor-rule helpers shared by the display control popup and
// the settings app. They only build Lua source; callers run `hyprctl eval`.

function quoteLua(value) {
    return `"${String(value).replace(/\\/g, "\\\\").replace(/"/g, '\\"')}"`;
}

function modeFor(monitor, width, height, refreshRate) {
    const prefix = `${width}x${height}@`;
    const requested = `${prefix}${Number(refreshRate).toFixed(2)}Hz`;
    return monitor.availableModes?.includes(requested)
        ? requested
        : (monitor.availableModes?.find(mode => mode.startsWith(prefix)) ?? "preferred");
}

function monitorRule(monitor, disabled, mirror, mode = "preferred", scale = "1") {
    let rule = `{ output = ${quoteLua(monitor.name)}, mode = ${quoteLua(mode)}, position = "auto", scale = ${quoteLua(scale)}, disabled = ${disabled ? "true" : "false"}`;
    if (mirror)
        rule += `, mirror = ${quoteLua(mirror)}`;
    return `${rule} }`;
}
