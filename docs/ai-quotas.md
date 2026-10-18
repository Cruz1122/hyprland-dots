# Subscription quotas and account isolation

Click the rotating bar emblem to open the quota curtain. Hover pauses rotation;
the resource pills retain their own consumption popup. OpenAI represents **Codex / ChatGPT**,
not developer API billing. Google represents **Google AI Pro via Antigravity**,
not Gemini web or Gemini API credits. No reported percentage or reset date is hardcoded.

## Set up and change accounts

Open **Settings → Services → Cuotas de IA y cuentas → Conectar cuentas…**, or
click the bar emblem. Account setup is GUI-only; no terminal is launched. Secrets
are sent on the backend's private stdin channel, never in command arguments.
Cancel stops pending OpenCode authorization work; late results cannot add an account.
Never paste credentials into chat, source files, shell arguments or settings JSON.

Provider IDs: `codex`, `opencode`, `antigravity`, `cursor`, `zed`, `claude`; the
Zed card also reads the built-in `grokbot` cache described below.

- **ChatGPT through OpenCode (default):** choose **Conectar** to use the fork's
  existing ChatGPT login, or **Iniciar sesión** for its browser PKCE flow. The
  quota bridge reads fresh `/wham/usage` data independently of model execution.
  No Codex CLI or Secret Service dependency is needed for this source.
  Expired access tokens fail closed: reauthorize in the dialog, or let OpenCode
  renew its own session. The quota reader never rotates a shared refresh token.
- **OpenCode Go through OpenCode (default):** reads the configured `opencode-go`
  API key, or `opencode` only when the former is absent. It supports both known
  usage envelopes, including rolling, weekly and monthly windows. No raw key is
  returned to Python or QML. Identity is explicitly unverified for Go.
- **OpenCode Go manual key:** choose **Introducir API key de Go** and supply a workspace API key after explicitly accepting the
  undocumented usage endpoint. A new key is tested before replacing an old one.
  The response currently does not prove account identity; aliases are user labels.
- **Legacy Codex CLI source:** existing saved accounts remain supported. Install/authenticate the official CLI yourself, then explicitly
  authorize following its active ChatGPT session. Quota queries use app-server
  with read-only sandbox/never-approval settings, not model prompts. Change the
  login with the official client; reconnect in this manager to invalidate cached
  readings. No independent native-account profiles are invented.
- **Antigravity (guided):** **Conectar** opens the official client's Google
  authorization. If `agy` is absent, **Instalar y conectar** explicitly installs a
  pinned, hash-verified official binary in the panel's private data directory.
  No sudo, shell profile edits, API key, or borrowed OAuth client is involved.
  `agy --version` must report at least 1.1.11 before the adapter can run the native
  `/usage` report. Older versions may treat it as a prompt and are never tried.
  Reports without identity are labelled **active session / identity unverified**.
  The background client runs outside projects with browser launchers blocked.
  It still uses the official CLI's global configuration; review that client's
  own integrations. This adapter does not recreate OAuth or probe local servers.
- **Cursor (normal browser, explicit opt-in):** enable the panel's browser link
  once, then connect using the browser/profile you already use. The extension
  reads usage first-party in Cursor's page, without exporting cookies or tokens.
  Identity is checked before and after usage.
  Pool labels follow community clients and must be checked against your dashboard.
- **Zed (normal browser, explicit opt-in):** the same browser link reads billing
  from `dashboard.zed.dev` using the existing web session and Zed's credentialed
  CORS contract. No new browser profile or editor/browser identity mixing.
  The panel displays the
  spending budget actually returned, not a guessed Student credit balance.
  Student includes $10/month, but this is never substituted for a missing limit.
  This source does not report the billing reset or verify the principal; those
  fields remain unavailable. Reconnect when the browser session expires.
- **Claude (official statusline, default):** sign in with the official Claude Code
  client. The GUI can explicitly install its pinned native binary when missing.
  Setup adds the panel's statusline wrapper to Claude Code settings, preserving
  unrelated settings and chaining any existing trusted statusline command. Only
  official `rate_limits` fields are persisted: no OAuth token, transcript, cwd,
  session ID or prompt. Claude Code publishes these limits after a genuine first
  response with Pro/Max; the panel does not send that message or create usage.
  Until then the card says **Esperando límites**, never 0% used. Capture time is
  retained, expired windows are discarded, and the file is checked every 5 seconds.
- **Grok Bot (local app cache):** the Zed card shows the **Grok Bot** weekly
  reading by default; its top-corner switch reveals the Zed budget instead. The
  reading is the one the Grok Bot desktop app already stores on disk
  (`~/.config/Grok Bot/sand-client-persistence`, the
  `*.weekly-usage.cache` entry). Only that entry is read, never the app's
  transcripts, cookies or secrets; no credential, endpoint, cookie export or
  browser profile is involved. The value is the app's own cached percentage until
  the app syncs again, so it is shown as read, not as a live request.
- **Advanced manual fallbacks:** the dialog keeps the previous Cursor/Zed cookie
  forms and the optional Claude Code OAuth access token
  (`sk-ant-oat01-…`), not an Anthropic API key. The read-only
  `https://api.anthropic.com/api/oauth/usage` adapter parses five-hour and weekly
  windows. It never generates messages, extracts credentials from another app,
  or refreshes the token. The endpoint is internal, may reject the client, and is
  not claimed to be a public third-party OAuth integration. No subscription or
  plan allowance is inferred. Identity remains unverified. Review provider terms
  before enabling any internal endpoint integration.

Cursor/Zed browser endpoints are not public third-party APIs. Their providers may
restrict automated access or the account; the GUI requires explicit opt-in and
does not claim vendor endorsement. No captcha, login challenge or access control
is bypassed. A successful login alone is insufficient: recognized usage must be
received before the account is registered. Unknown schemas fail closed.

## Guided client installation and browser sessions

The dialog uses one primary action, **Conectar** or **Instalar y conectar**.
Manual secret fields are hidden behind **Configuración manual (avanzada)**.
During authorization the curtain temporarily hides (without destroying the job)
so its exclusive keyboard focus cannot prevent typing in the browser. It returns
on completion/error. Cancel and backend exit release that state.
Click the bar emblem during authorization to bring back the pending dialog and
its Cancel button, without needing to wait for the browser callback timeout.
The dialog also has **Plegar overlay y continuar**. This hides the layer-shell
panel without dismissing its dialog, cancelling its backend request, or clearing
an authorization code. Click the AI emblem in the bar to restore it. Use the
separate **Cancelar** button only when you intend to abort login.

### Antigravity authorization codes

If the official client uses the URL-and-code flow, finish Google sign-in, return
to the panel using the bar emblem, and paste the **new** code into **Código de
autorización** → **Continuar con el código**. Do not paste codes into chat.
The field is masked and cleared after submission/cancel. The code travels only
over the private backend stdin and the owned client's controlling PTY (echo
disabled), never through shell arguments, quota caches, settings or result frames.
A single-threaded exec shim attaches the controlling terminal; no unsafe threaded
`preexec_fn` is used. Codes are bound to the pending request and limited to 2048
printable authorization-code characters. Closing the dialog cancels that process.

### Browser link: keep the user's existing login

Cursor/Zed now default to `browser-extension`, not a fresh Chromium profile.
One-time explicit setup in their dialog:

1. **Configurar conexión en mi Brave (una vez)** copies the reviewed local extension and
   registers its user-level Native Messaging host. This does not enable it silently.
2. **Copiar carpeta**, then **Abrir gestor de extensiones**. Enable Developer mode,
   choose **Load unpacked**, and select that folder. The manager opens in the
   existing browser, with no `--user-data-dir` or debugging flags.
3. Return with the bar emblem, accept the internal-endpoint integration, and
   **Conectar**. Existing website sessions are reused; a site may still require
   reauthentication if its own session has expired.

If **Conectar** reports that the browser link is missing, the dialog now prepares
the local extension automatically, copies its folder path, and opens the extension
manager in your existing Brave window. Follow the visible steps there: enable
Developer mode, choose **Load unpacked**, select the copied folder, return with
the AI bar emblem, and press **Conectar** again. This is a one-time browser
extension activation, not another provider login. The old manual cookie form is
explicitly labeled advanced/unreliable; an expired session cookie or OAuth code
is not a substitute for the browser flow.

The extension has host permissions only for Cursor/Zed origins and permissions
for native messaging, isolated script execution, alarms, and session storage for
IDs of its own temporary tabs. It requests neither `cookies` nor `debugger`.
It reads known usage fields (and a hashed Cursor identity) in the browser, sends
only sanitized quota data over Native Messaging, and never exports a session store.
The host accepts only its fixed extension origin and bounded 1 MiB framed messages.
Single-use 180-second tickets are bound to explicit login or selected account and
generation. No loopback HTTP listener is exposed. Disabled/unselected accounts
are not requested. Captured timestamps are preserved; opening a site alone does
not register a connected account.

Files live under `$XDG_DATA_HOME/illogical-impulse/ai-quotas/browser-link` and
`$XDG_STATE_HOME/illogical-impulse/ai-quotas/browser-link`. Host manifests are scoped
to the extension ID in the user-level NativeMessagingHosts directories for Brave,
Chromium and Chrome. No browser Preferences, personal profiles or existing browser
credentials are read or rewritten. Background refresh is normally every 180 seconds;
the extension checks for work with a 30-second alarm. It removes only its own
inactive temporary tabs, not user-owned or activated tabs.

Native installation is opt-in, Linux x86_64 only, and never happens on hover or
background polling. `guided.py` pins official agy 1.4.2 (SHA-512) and Claude Code
2.1.302 (SHA-256) downloads, refuses HTTP redirects, bounds download size/time,
checks the digest before publishing an executable, and extracts only the regular
`antigravity` tar member. No remote installer script is executed. Managed files
live under `$XDG_DATA_HOME/illogical-impulse/ai-quotas/clients`; existing clients on
PATH are preferred and never overwritten. Updating pins is a deliberate code
change. Source: [agy installer](https://antigravity.google/cli/install.sh),
[Claude release manifest](https://downloads.claude.ai/claude-code-releases/2.1.302/manifest.json).
Pinned hashes provide integrity against the reviewed release, not an independently
verified publisher signature. Official-client login remains interactive in the
browser; PTY integration may need adjustment if a future client changes prompts.

The legacy `browser-session` source remains compatible, but the GUI migrates
reconnection to the normal-browser link. That legacy fallback uses Brave,
Chromium or Google Chrome. Its profiles are private and
feature-owned under `$XDG_STATE_HOME/illogical-impulse/ai-quotas/browser-sessions`.
CDP uses inherited pipes, not a remote-debugging TCP port; the Chromium sandbox
stays enabled. Browser-owned profile files follow the browser's own format and
permissions inside a 0700 directory. No personal profile is imported. Login is
visible and bounded; refresh is headless and cannot initiate a visible login.
Closing/cancelling a login does not undo cookies already saved by the browser.
Removing panel metadata stops polling but does not erase that dormant profile;
it never signs out an existing personal browser/editor session.

Claude's original statusline object is backed up privately. Removing its panel
account restores that object only if the wrapper is still the current command,
preserving unrelated settings edits. Relocated copies of the wrapper are not
chained recursively. The wrapper passes the original JSON to the user's existing
trusted command, just as Claude Code did before integration.

The official account links in the dialog only assist authorization. Opening a
website is never treated as a successful connection: the usage adapter must
return recognized measurements before a manual credential is stored.

## OpenCode fork bridge

Requires Bun and the modified fork at `~/dev/opencode`, including
`packages/opencode/script/quota-bridge.ts`. Set `OPENCODE_QUOTA_ROOT` in the shell's
environment if the checkout lives elsewhere. No rebuild of the installed OpenCode
binary is required: the backend executes the bridge directly from the checkout.

Transport is one request per owned subprocess, NDJSON over private stdin/stdout:
`{"action":"usage","provider":"codex"}` or `opencode`. Explicit ChatGPT login uses
`{"action":"login","provider":"codex"}` and emits an interim `authorize` frame,
followed by a final result. Only the validated `https://auth.openai.com/oauth/authorize`
URL is sent to the desktop browser. Login is asynchronous, cancellable, and bounded
to 180 seconds; normal queries are bounded to 25 seconds. No unauthenticated local
HTTP quota service is exposed. The OAuth callback binds only to `127.0.0.1:1455`.

The bridge uses the fork's Auth service. Usage reads do not write credentials and
ignore inherited `OPENCODE_AUTH_CONTENT`. Each query compares the auth entry before
and after the request and discards a changed session. ChatGPT account IDs are
hashed; the bridge never exports access/refresh tokens. HTTPS redirects and
unrecognized quota schemas are rejected; response bodies are capped at 1 MiB.
Browser login updates the fork's existing active ChatGPT login, not a separate
profile. Cancelling does not undo an authorization already completed in OpenCode.

The legacy isolated-browser transport also supports `cursor` and `zed`. A `browser` progress frame
means the bridge has opened its own window; the GUI must not open a second URL.
These providers return bounded named `windows` (including actual spend/budget),
not synthetic primary/secondary percentages. The browser session is an active
session source, not multiple fictitious pinned accounts. Headless refresh and
visible login for a provider are serialized.

Manual credentials require `python-secretstorage` and a running, unlocked
Secret Service collection. On Arch/CachyOS, installing the dependency is an
explicit system operation:

```sh
sudo pacman -S --needed python-secretstorage
```

This feature never installs it, unlocks the keyring or launches login from hover.
Unlock your collection through the system's existing password/keyring manager.
Official-client installation/sign-in are explicit GUI actions, never background setup.

## Security and state

Only the quota backend and the OpenCode bridge access their respective secrets. Per-credential Secret Service entries use
`application=illogical-impulse-ai-quotas`, provider and random credential reference.
They are unrelated to chat API keys or the TOTP authenticator. No provider refresh
token is copied or rotated by the quota backend; official clients own their login.

Private metadata lives under
`$XDG_STATE_HOME/illogical-impulse/ai-quotas` (default `~/.local/state/...`), sanitized
cache under `$XDG_CACHE_HOME/illogical-impulse/ai-quotas`. Directories are 0700,
files 0600. These are runtime data, never deployment inputs or Git contents.

Account/credential changes bump a persistent generation. The backend checks the
selection again before publishing results, discarding late responses. Cache keys
include opaque account ID/generation and validate credential/source references.
There is no fallback to another account, no fake zero when data is missing, and no
use of a browser account to label an editor account. Native modes explicitly follow
the active client instead of pinning unverifiable accounts. Cached readings show
their age; external client switches are observed at the next refresh, not by an
undocumented live login watcher.

Polling is shared across monitors/processes by file locks and cache, typically
every 180–195 seconds, with a 30-second manual refresh floor and exponential
failure backoff/Retry-After. Hover itself performs no request. Measurements older
than 15 minutes are hidden. HTTPS redirects are rejected; no global TLS bypass.
CLI output and execution time are bounded. Raw errors/headers/tokens are never
forwarded to QML or logs. Reset instants are exposed only as the machine-readable
`resetsAt`; the UI renders a relative countdown ("Falta 1 hora"), never an absolute
time or timezone.
Claude statusline reads use a 5-second local retry/poll without inventing a newer
measurement timestamp. Native auth URLs are allowlisted separately for Google
and Claude, in both backend and QML. Install plus login has a 365-second GUI
deadline, with bounded downloads and 180-second native authorization.

## Endpoint stability and evidence

All network access requires explicit setup. These are subscription quota reads,
not requests to generate content, redeem reset credits or change billing.

- OpenCode: `GET https://opencode.ai/zen/go/v1/usage` (Bearer API key).
  [Official proxy route](https://github.com/anomalyco/opencode/blob/dev/packages/console/app/src/routes/zen/go/v1/usage.ts),
  [response evidence](https://github.com/anomalyco/opencode/issues/53701).
- Codex: official local `initialize`, `account/read`, `account/rateLimits/read`
  protocol. [Source](https://github.com/openai/codex/blob/main/codex-rs/app-server-protocol/src/protocol/v2/account.rs).
  Optional account identity/durations are not invented when absent.
- Antigravity: native version-gated `agy -p /usage --output-format json`.
  [CLI docs](https://www.antigravity.google/docs/cli/headless/),
  [community adapter notes](https://github.com/steipete/CodexBar/blob/main/docs/antigravity.md).
  Only a successful `command.name=usage` report with quota groups is parsed;
  inference token counters are not quotas.
- Cursor: `GET https://cursor.com/api/auth/me` and `/api/usage-summary` through the
  normal-browser link (or legacy isolated browser / explicitly supplied cookie).
  [Adapter evidence](https://github.com/steipete/CodexBar/blob/main/docs/cursor.md).
- Zed: `GET https://cloud.zed.dev/frontend/billing/usage` through the normal-browser
  link (or legacy isolated browser / manual cookie). [Adapter evidence](https://github.com/steipete/CodexBar/blob/main/docs/zed.md),
  [Student plan](https://zed.dev/docs/account/plans-and-pricing).
- Claude statusline: [official rate-limit contract](https://code.claude.com/docs/en/statusline#rate-limit-usage).

Community/internal contracts may change. Unknown schemas fail closed. This is
not a guarantee of account compatibility or a statement that the provider supports
third-party integrations. Check each enabled source against your dashboard.

## Verify and roll back

`scripts/verify.sh` runs synthetic parser, account race/isolation, vault and UI
contract tests without network, real credentials or a desktop. Live A/B switching,
login expiry and locked-keyring checks require explicit user setup and are not
claimed by a passing offline suite. No credentials belong in test fixtures.
The gate also requires Node.js 22+ for browser-extension tests. Where Bun, Brave
and the local fork exist, a temporary-profile smoke test loads the actual
extension and exercises Chrome Native Messaging end-to-end with empty account
state; it never authenticates or opens provider pages. CI skips that optional
machine-dependent smoke while retaining deterministic broker/protocol tests.

Disable a provider to stop polling it. Removing a saved account deletes only its
own bar credential and local metadata/cache; it does not sign out the editor or
revoke the provider session. To revert the UI, restore the backed-up emblem,
Resources and ServicesConfig files; new files may remain unused. Preserve the
existing resource pills, battery contrast, heart and authenticator. Never reset
the whole dirty repository or erase the shared keyring.

Scoped code-only deployment (preview first):

```sh
python3 scripts/deploy-ai-quotas.py
python3 scripts/deploy-ai-quotas.py --apply
python3 scripts/deploy-ai-quotas.py --restore /path/printed/by/deploy
```

The explicit manifest never captures account metadata or secret state. It backs
up existing live code privately and restores only if deployment/original hashes
still match. New files can remain unused after restoring the entry points.
If atomic file replacement does not trigger the shell's file watcher, use the
existing reload action in the right sidebar after deployment or restoration.
Do not kill/restart the desktop session just to reload these components.
