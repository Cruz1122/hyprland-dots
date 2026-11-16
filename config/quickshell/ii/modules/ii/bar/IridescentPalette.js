.pragma library

// Shared cool iridescent palette (bar pills, launcher panel edge light).
// Hue swings teal (0.45) <-> violet (0.79) around blue. A sine keeps the loop
// seamless without wrapping through the warm hues.
const hueCenter = 0.62;
const hueSwing = 0.17;
// Fraction of the oscillation cycle visible across one element at any instant.
const spread = 0.4;

// phase: 0..1 animation progress; position: 0..1 along the element.
function hue(phase, position) {
    return hueCenter + hueSwing * Math.sin((phase - position * spread) * 2 * Math.PI);
}
