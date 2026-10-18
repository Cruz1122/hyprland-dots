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
private cache paths. If there is no valid photo or renderer template, the UI
uses Grok's neutral default: a white circle, not the application icon.
