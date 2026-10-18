.pragma library

// Input order is the stable tie-breaker; sorting never mutates the service data.
function topTwo(candidates) {
    return candidates.map((item, order) => ({
        id: item.id,
        icon: item.icon,
        value: Math.max(0, Math.min(1, item.value)),
        valid: item.available !== false && typeof item.value === "number" && Number.isFinite(item.value),
        order: order
    })).filter(item => item.valid)
        .sort((a, b) => b.value - a.value || a.order - b.order)
        .slice(0, 2);
}

function severity(value) {
    return Math.max(0, Math.min(1, (value - 0.3) / 0.6));
}

function mix(start, end, amount) {
    return {
        r: start.r + (end.r - start.r) * amount,
        g: start.g + (end.g - start.g) * amount,
        b: start.b + (end.b - start.b) * amount,
        a: 1
    };
}

function luminance(color) {
    function linear(value) {
        return value <= 0.04045 ? value / 12.92 : Math.pow((value + 0.055) / 1.055, 2.4);
    }
    return 0.2126 * linear(color.r) + 0.7152 * linear(color.g) + 0.0722 * linear(color.b);
}

function contrast(first, second) {
    const a = luminance(first);
    const b = luminance(second);
    return (Math.max(a, b) + 0.05) / (Math.min(a, b) + 0.05);
}

// Evaluate the actual animated background on every frame. Never animate the
// foreground through low-contrast intermediate colors.
function foreground(background, preferred) {
    if (contrast(background, preferred) >= 4.5)
        return preferred;
    return luminance(background) > 0.179 ? "#000000" : "#ffffff";
}
