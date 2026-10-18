# Generated Grok avatar motion frames

This directory is generated from the native 0.71.2 keyframes in the sibling
`grok-avatar-animations` directory by
`scripts/grok-generate-interframes.py` with `--steps 4`.

Each sequence has 181 SVG frames. The original 46 Grok keyframes are kept
exactly at indices `0, 4, 8, ..., 180`; the three frames between compatible
keyframes are vector interpolations generated offline. Intervals where the
native SVG changes path topology keep the preceding keyframe instead of
inventing an invalid morph. Closed contours are aligned for winding and cyclic
start before interpolation because Grok's exporter can re-anchor the same
shape between keyframes; without that alignment, a valid SVG could briefly
fold into a self-intersecting shape and appear to blink.

The four-times denser sequence preserves Grok's original 100 ms keyframe
cadence at 25 ms per generated frame. It is read-only integration data and is
never written to Grok Bot's persistence directory. Quickshell loads only the
currently displayed frame (plus the transition layer) and lets Qt Quick's
shared `Image` cache reuse decoded SVG textures; it does not retain a hidden
181-image preloader for every avatar sequence.
