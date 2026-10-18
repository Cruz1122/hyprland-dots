# Grok avatar renderer output

The `*.svg.tmpl` files are URL-encoded output from Grok Bot 0.71.2's bundled
avatar renderer (`aP()` / `ZN()`). They preserve Grok's generated SVG paths,
mask, viewBox, and transforms; they are not redrawn in QML or replaced with
Material shapes. `palette.json` records the light/dark ink pairs from Grok's
`Zf` palette. The local roster bridge strips Grok's CSS-variable theme style,
then emits light and dark variants with the exact palette ink as a literal SVG
fill. This preserves the original paths while avoiding Qt's unsupported CSS
custom properties.

The templates contain no agent names, IDs, conversations, account data, or
private cache paths. When the roster omits a bot's shape or color, the bridge
replicates Grok Bot 0.71.2's ID-derived defaults: its eight-shape subset and
FNV-1a/seeded-PRNG color selection (which excludes automatic `black`). Explicit
valid roster metadata remains authoritative. If there is no valid photo or
renderer template, the UI uses Grok's neutral fallback: a white circle, not
the application icon.

The active 0.71.2 app also contains a separate native motion renderer
(`GrokBotMark`) with expression/reaction states such as `happy`, `excited`,
`laughing`, `curious`, `surprised`, `sad`, and `scared`. The extracted native
state SVG sequences live in the neighboring `grok-avatar-animations` directory;
this directory remains the exact still fallback for photos, unsupported
shape/color pairs, and missing animation assets. No animation state is written
back to Grok.
