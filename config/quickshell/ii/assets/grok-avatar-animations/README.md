# Native Grok avatar motion

These SVG frames are extracted from the native `GrokBotMark` renderer shipped
inside the active Grok Bot 0.71.2 AppImage. They are not hand-drawn QML
animations: each frame contains the renderer's original vector paths, masks,
eye cutouts, transforms, and state-specific expression output.

The current capture contains 46 native frames at 100 ms per frame for every
combination of the eight shape/color pairs present in the active roster and the
following display states:

- `neutral`
- `attentive`
- `surprised`
- `excited`
- `happy`
- `laughing`
- `angry`
- `sad`
- `scared`
- `suspicious`
- `confused`
- `curious`
- `proud`
- `shy`
- `unimpressed`
- `sleepy`

The directory `attentive` is captured from Grok's native `listening` state,
`unimpressed` from `bored`, and `sleepy` from `sleeping`; those are the
closest names exposed by the active 0.71.2 renderer. The other names map
directly to native state recipes.

The eight shape/color pairs are:

- `hex-green` — Benjamín
- `blob-violet` — Vigilante MN5
- `heart-red` — Mr Greedy
- `sparkle-magenta` — Mi Bamba
- `teardrop-black` — dr eggbot
- `star-yellow` — Tío Rico
- `cloud-blue` — Alfredo
- `tablet-violet` — Gustavo

The renderer's body color was converted from Grok's CSS custom property to a
literal color because Qt's SVG image backend does not resolve that browser CSS
variable. The generated DOM IDs use a safe `motion-*` prefix because some Qt
SVG readers reject IDs beginning with a UUID digit; those IDs are only internal
`<use>` references and do not affect the drawing.
Geometry and animation data are unchanged. `GrokAvatar.qml` advances the
frames with a small QML timer, retains the previous complete frame while the
next SVG is decoded, and runs the captured slice as a ping-pong loop. The
ping-pong traversal makes the last frame of each cycle exactly frame 000,
avoiding a visible jump or tearing at the loop boundary. The native layer is
scaled by 1.45x inside the avatar item to match the silhouette size of Grok's
static renderer without changing the clickable bounds.

The bar uses `curious` while an unread avatar is hovered and `excited` while
it is pressed. Notification-group avatars use `attentive` while the group is
under the pointer; otherwise they use `neutral`. Callers can provide another
supported state through `GrokAvatar.nativeAnimationState`.

The assets are deliberately kept outside Grok's persistence directory. They
are read-only integration assets and are never written back to the Grok app.
They should be regenerated if Grok changes the native motion renderer or the
roster contains a new shape/color pair that should animate.
