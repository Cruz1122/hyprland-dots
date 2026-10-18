# Native Grok avatar motion

These SVG frames are extracted from the native `GrokBotMark` renderer shipped
inside the active Grok Bot 0.71.2 AppImage. They are not hand-drawn QML
animations: each frame contains the renderer's original vector paths, masks,
eye cutouts, transforms, and state-specific expression output.

The current capture contains 46 native frames sampled at 100 ms per frame for
every combination of the eight shape/color pairs present in the active roster
and the following display states:

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
Geometry and animation data are unchanged. The offline-generated sibling
directory `grok-avatar-animations-interpolated` adds three vector samples
between compatible native keyframes while preserving every original frame.
The runtime renders each generated vector frame at a fixed 112 px texture size
with smooth filtering and no mipmap blur pass. The generated sample index
advances every 25 ms, preserving the original 100 ms keyframe duration without
speeding the extracted motion up. When the requested native state changes, the
current frame keeps advancing and the old/new state layers cross-fade over
220 ms; the sequence is not reset or cut at frame 000. It runs the captured
slice as a ping-pong loop, making the last frame of each cycle exactly frame
000 and avoiding a visible jump or tearing at the loop boundary. The native
layer is scaled by 1.45x inside the avatar item to match the silhouette size
of Grok's static renderer without changing the clickable bounds.

The bar uses `curious` while an unread avatar is hovered and `excited` while
it is pressed. Notification-group avatars use `attentive` while the group is
under the pointer; otherwise they use `neutral`. Callers can provide another
supported state through `GrokAvatar.nativeAnimationState`.

`GrokAvatarMotionCache.qml` keeps one shared compositor clock for the bar and
notification avatars. Each visible `Image` uses Qt Quick's shared image cache
at a fixed 112 px texture size, which is large enough for the current 38 px
notification avatar after its 1.45x native-layer scale and is also reused by
the smaller bar avatar. Individual avatars do not create their own timers or
hidden per-frame preloaders.

The cache publishes one shared clock driven by a single `FrameAnimation`
hosted by an active `GrokAvatar` in the scene graph. Only the elected clock
owner runs that compositor callback; if it is destroyed, another avatar takes
over. On the active eDP-1 output this callback follows the 144.003 Hz
compositor refresh, while the selected generated SVG frame advances every
25 ms (about 40 samples per second). The singleton publishes a new sample
only at those boundaries, so avatars do not recompute their phase from the
144 Hz elapsed-time signal individually. This keeps the animation's original
speed while avoiding per-avatar timers and unnecessary binding work; the
display remains compositor-synchronised at 144 Hz even though the extracted
motion does not contain 144 unique vector samples per second. State changes
continue to cross-fade over 220 ms, and the ping-pong sequence returns to
frame 000 at the loop boundary.

The assets are deliberately kept outside Grok's persistence directory. They
are read-only integration assets and are never written back to the Grok app.
They should be regenerated if Grok changes the native motion renderer or the
roster contains a new shape/color pair that should animate.
