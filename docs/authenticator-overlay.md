# Authenticator overlay

The authenticator is a full-screen curtain with a read-only view of saved TOTP
accounts. Its header displays a large `heart_smile` and extra-bold
**AUTENTICADOR** (weight 800), with a 2 px icon/title gap. The body is split into
left/right panels at 20%/80% of the width available after the gap. The left panel
shows codes, issuer/account captions below them, and circular countdowns on the
right of each row. The right panel presents six centered options in a 3×2 grid:
screen QR capture, QR image, manual secret, pasted otpauth URI, Google
Authenticator migration image, and encrypted backup import. All six methods are active once the
secure account store has loaded. There are no visible add/remove buttons;
deletion is available from a stored-code row's right-click menu. The existing
keyring item and Python command format are unchanged; account secrets are passed
to the backend over stdin, not command arguments.

The left panel has centered loading, empty and generic error states. The empty
state is an icon with **Aún no tienes códigos guardados.** underneath. Failed
keyring lookup, malformed data or failed code generation do not masquerade as an
empty account list. An explicit retry action is available; raw errors and secrets
are not rendered. Missing dependencies also produce a recoverable error state.

The header and panels use the normal surface colors from the current theme; no
layout-debug color guides remain.

## Interaction contract

- Click the heart in the top bar to open on that bar's monitor.
- `Super+O` toggles on the focused monitor when closed.
- One overlay is presented at a time. Its monitor stays fixed through opening,
  closing and a reversed closing animation.
- The heart is hidden in the bars throughout presentation, without collapsing
  its layout slot. The clock/sidebar interaction is independent of its button.
- `Esc`, the centered mobile-style bottom handle and `Super+O` close the curtain.
  The handle is a clickable button with a 112×48 logical-pixel hit area, keyboard
  focus indication and an accessible name. Drag it upward to move the curtain;
  release after 72 logical pixels to dismiss, otherwise it expands back. Cancelled,
  downward or short drags do not generate a tap. The handle follows the revealed
  edge while the body layout retains its full-screen dimensions.
  The header has no close icon. Clicking body content does not dismiss it.
- Valid code rows have a pointer cursor and copy the current raw digits when
  clicked (or activated with the keyboard). The code is re-read and validated
  at activation, so an expired rendered value is not copied. A gold highlight
  and **Copiado** caption fade in immediately and reset after 1.2 seconds, with
  stable row geometry. Codes awaiting refresh cannot be copied. Clipboard writes
  use `Quickshell.clipboardText`, not a shell command; copying is only explicit.
  The desktop's clipboard manager may retain a copied code in its history.
- Right-click a stored-code row to open a confirmation dialog. **Cancelar**
  leaves the keyring unchanged; **Borrar** removes that entry from the existing
  keyring store. There is no one-click destructive path.
- Reveal is top-to-bottom; exit is bottom-to-top. The layout has fixed dimensions
  inside a clipping viewport, so it does not reflow during reveal.
- The viewport expands from the top bar's height to the full screen and contracts
  back into that band. Cubic ease-in/out softens both ends (at least 520 ms opening,
  420 ms closing for a full traversal). Interrupted travel starts at its current
  progress, with a 160 ms minimum to avoid near-end snaps. A short opacity blend
  hides the appearance/disappearance of the initial/final bar-sized surface.
- Session lock or removal of the selected monitor tears down immediately.
- **Capturar QR:** selecting this option closes the authenticator before opening
  the existing rectangular region selector, after the secure keyring store has
  loaded successfully. Select just the QR; `Esc` cancels.
  The selected area is cropped locally and passed to the existing QR/TOTP parser,
  including Google Authenticator migration payloads. Valid accounts are added to
  the existing keyring-backed store, then the authenticator returns to its source
  monitor with a short generic status message. Invalid/unsupported QR contents do
  not enter storage. Cancellation, no QR, parser errors and timeouts are distinct.
  Those results are shown in a modal with an icon, explanatory copy and an
  **Entendido** button, not inline in the options grid.
  This flow does not use the clipboard, open decoded links, make network requests,
  or log the QR contents. The full-screen freeze and cropped image use temporary
  files with mode 0600 (including when reusing an existing capture path); both
  are removed on success, failure, timeout or cancellation. Region selection is
   capped at 60 seconds; image identification has a 5-second limit, and crop/QR
   parsing steps have 10-second process limits. The overall image read allows
   50 seconds for the bounded fallback retry.
- **Abrir imagen:** opens a local image picker for PNG/JPEG/WebP/BMP/TIFF. Images
  are limited to 25 MiB and 50 megapixels; the selected file is preserved. QR
  decoding reuses the local parser and retries with grayscale/Otsu binarization
  for screen-scaled, anti-aliased codes. The curtain closes before opening the
  picker so its native window is not hidden behind the overlay, then returns to
  the same monitor after selection or cancellation.
- **Clave manual:** opens a form for issuer, account, Base32 secret, algorithm,
  six/eight digits and period. The secret is masked and validated before it is
  merged into the existing keyring-backed store.
- **Pegar URI:** explicitly reads the clipboard and accepts a validated
  `otpauth://totp/` URI. It does not write to the clipboard or log the URI.
- **Migrar cuentas:** opens a local image picker restricted to a Google
  Authenticator migration QR; all parsed accounts are validated before saving.
- **Importar copia:** reads an `ii-authenticator-v1` encrypted JSON backup up to
  5 MiB and prompts for a masked password. Decryption uses the existing Python
  backend with the password on stdin; decrypted accounts are validated before
  merging. Its native picker also opens after the curtain closes and returns to
  the same monitor after selection or cancellation. Wrong passwords and malformed
  copies produce a generic modal error.

All add methods require the secure keyring store to have loaded successfully.
Native file dialogs are local-only; no files are uploaded or decoded links opened.
All methods report success/failure in the same icon-and-copy modal pattern.
Plain-text error details, QR payloads, secrets and backup passwords are not
logged.

The public `authenticatorOpen` flag is the requested state;
`authenticatorPresented` includes the exit animation. `authenticatorScreenName`
identifies the source monitor. Existing IPC calls remain supported:

```sh
qs -c ii ipc call authenticator toggle
qs -c ii ipc call authenticator close
```

These commands change the live desktop. The overlay uses an exclusive keyboard
layer and does not register with or modify the shared `GlobalFocusGrab` service.

## Code lifecycle

`AuthenticatorStore` is activated only by the loaded overlay and paused/cleared
on its destruction. Saved accounts are validated before use; delegates receive
only key, issuer, account, digits and period, never the Base32 secret. Codes are
refreshed on opening, account changes or time-window changes, not every clock
tick. A 100 ms visible clock animates each account's own remaining fraction;
6- and 8-digit codes are grouped for readability. Expired results are hidden
until a result for the current time window arrives. Late results after closure
or a newer request are discarded. Keyring and code processes have timeouts.

## Verification

Run `bash scripts/verify.sh` for integration contracts, backend tests, synthetic
QR-capture helper tests and isolated component/model tests. Qt 6 component tests use an injected fake store in an
offscreen window; headless store tests use a fake `secret-tool`, public synthetic
accounts and an isolated shell. They do not access the live keyring or desktop.
These are skipped explicitly if Qt 6/Quickshell is unavailable. Static contracts
alone do not establish animation, input routing or monitor placement.

There are also opt-in live tests. They open and close the overlay and send
`Esc`/`Tab`/`Space` to it; prerequisites are a running `ii` shell, Hyprland, and
`wtype`. Start with the overlay closed and do not interact during the test:
These opt-in tests now display the real saved accounts and can prompt to unlock
the keyring. Do not use them for synthetic-only or screenshot-based verification.

```sh
HYPRLAND_DOTS_AUTHENTICATOR_RUNTIME=1 python -m unittest tests.test_authenticator_runtime -v
```

These check full-screen focused-monitor placement, keyboard close, and survival
of the same layer surface across an interrupted exit. They do not measure the
visual reveal or exercise the bar's mouse routing. The default suite skips them.

In a running Hyprland/Quickshell session, check both opening paths, all three
closing paths, rapid reversals, the heart's reserved slot, focus return and the
empty/loaded account states and upward drag. Multi-monitor selection and monitor unplugging need suitable
hardware. Lock testing is disruptive and should be performed explicitly by the
desktop user.

Implementation: `GlobalStates.qml`, `modules/common/authenticator/Authenticator.qml`,
`AuthenticatorCurtain.qml`, and `modules/ii/bar/BarContent.qml` under
`config/quickshell/ii/`. Deploy only these affected paths when the live tree has
unrelated differences. Back up those paths first; manual recovery restores only
them and removes the new curtain file if reverting to the previous UI. Do not
use a full-tree restore or an automatic rollback for this change.

After deploying, confirm a fresh `Configuration Loaded` entry in
`qs -c ii log --tail 20 --log-times` and visually verify the new layout. File
equality alone does not prove that the running QML engine has reloaded; unchanged
saves are ignored by the watcher, and a replaced component can remain cached.
