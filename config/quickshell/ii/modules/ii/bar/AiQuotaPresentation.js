.pragma library

// The dialog can be opened before the backend's first asynchronous frame arrives.
function defaultSource(provider) {
    switch (provider) {
    case "codex": case "opencode": return "opencode-bridge";
    case "cursor": case "zed": return "browser-extension";
    case "antigravity": return "agy-cli";
    case "claude": return "claude-statusline";
    default: return "";
    }
}

// A backend frame emitted before it processed a selection must not resurrect
// the old account after the UI has already cleared it.
function selectionAcknowledged(pending, selectedId, snapshot) {
    return selectedId === pending.accountId && snapshot
        && snapshot.generation >= pending.generation;
}

function resourceHovered(groupHovered, emblemHovered) {
    return groupHovered && !emblemHovered;
}

function authorizationUrlAllowed(value, provider) {
    if (typeof value !== "string" || value.length > 8192) return false;
    if (provider === "cursor") return value === "https://cursor.com/dashboard";
    if (provider === "zed") return value === "https://dashboard.zed.dev/account";
    if (provider === "antigravity")
        return /^https:\/\/accounts\.google\.com\/o\/oauth2\/(?:v2\/)?auth(?:\?[^#\r\n]*)?$/.test(value);
    if (provider === "claude")
        return /^https:\/\/(?:claude\.ai|platform\.claude\.com|console\.anthropic\.com)\/oauth\/authorize(?:\?[^#\r\n]*)?$/.test(value);
    return /^https:\/\/auth\.openai\.com\/oauth\/authorize(?:\?[^#\r\n]*)?$/.test(value);
}

// A snapshot with a bound account id means credentials are configured, which is
// what chooses between the "connect" affordance and the availability bars.
function connected(snapshot) {
    return !!(snapshot && snapshot.accountId);
}

// Two columns once a provider reports more than two quota windows, one otherwise.
// Keeps each bar wide enough to stay readable while compacting tall stacks.
function windowColumns(count) {
    return (typeof count === "number" && count > 2) ? 2 : 1;
}

// The lone trailing bar of an odd window set spans the whole row instead of
// leaving half of it empty.
function spansFullRow(index, count, columns) {
    return columns > 1 && count % 2 === 1 && index === count - 1;
}

// Human-readable time left until a quota window resets. The UI shows this
// relative phrasing only; absolute reset instants and timezones are deliberately
// not surfaced. Returns null when the provider reported no usable instant.
function resetCountdown(resetsAt, nowMs) {
    if (typeof resetsAt !== "string" || !resetsAt) return null;
    const target = Date.parse(resetsAt);
    if (!isFinite(target)) return null;
    const now = (typeof nowMs === "number" && isFinite(nowMs)) ? nowMs : Date.now();
    const minutes = Math.round((target - now) / 60000);
    if (minutes <= 0) return "Se reinicia ahora";
    if (minutes < 60) return minutes <= 1 ? "Falta 1 min" : "Faltan " + minutes + " min";
    const hours = Math.round(minutes / 60);
    if (hours < 24) return hours <= 1 ? "Falta 1 hora" : "Faltan " + hours + " horas";
    const days = Math.round(hours / 24);
    return days <= 1 ? "Falta 1 día" : "Faltan " + days + " días";
}

// Remaining allowance for a quota window as a 0..100 percentage, or null when the
// provider reported no usable numbers. Never assume 0% used or a full allowance.
function remainingPercent(window) {
    if (!window) return null;
    if (window.usedPercent !== null && window.usedPercent !== undefined)
        return Math.max(0, Math.min(100, 100 - window.usedPercent));
    if (window.usedAmount !== null && window.usedAmount !== undefined
        && window.limitAmount !== null && window.limitAmount !== undefined && window.limitAmount > 0)
        return Math.max(0, Math.min(100, 100 * (1 - window.usedAmount / window.limitAmount)));
    return null;
}
