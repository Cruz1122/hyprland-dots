# Settings app

The settings app (`config/quickshell/ii/settings.qml`, opened with `SUPER+I`
or the sidebar button through `scripts/settings/open-settings.sh`, which
focuses an open window instead of starting a second one) is a separate
Quickshell process (`qs -p …/settings.qml`). It edits shell
options (`config.json`), Hyprland options, and selected system settings. Every
setting it shows must have a real consumer; retired features stay hidden.

This document is the contract the implementation follows. Paths are relative
to `config/quickshell/ii` unless they start with `config/`, `scripts/`,
`tests/` or `docs/`.

## Process model

- The main shell (`qs -c ii`) and the settings app both load `config.json`
  through `Config` (`modules/common/Config.qml`). Writes rewrite the whole
  file and the last writer wins, so the settings app **only writes on user
  interaction**: never on load, never from bindings. It uses
  `Config.readWriteDelay = 150` so bursts coalesce into one write.
- `Config` writes synchronously (`blockWrites`, a few milliseconds for this
  file) and skips a file-change reload while its own write is pending, then
  applies a reload before returning (`waitForJob`). An asynchronous write
  re-applied the data it wrote when it finished, undoing a change made while
  it was in flight, and a reload that ran before a pending write put the old
  value back; either way the change was lost
  (`tests/test_config_write_race.py`).
- The settings process must not instantiate services with side effects:
  `Battery`, `Hyprsunset`, `Brightness`, `Notifications`, `Weather`, `Idle`,
  `Ai`, `AiQuotaUsage`, `Cliphist`, `ConflictKiller`, `Updates`, `SongRec`,
  `TimerService`. It talks to the main shell through IPC
  (`qs -c ii ipc call <target> <function> [args]`) and reads hardware state
  through Quickshell modules directly (`Quickshell.Services.Pipewire`,
  `Quickshell.Services.UPower`, `Quickshell.Hyprland`).
- External commands always run as argv arrays (`Process.command`,
  `Quickshell.execDetached([...])`). No `bash -c`, `sh -c` or string-built
  shell commands.

## Layout

Paths are relative to `config/quickshell/ii/`, which is installed as
`~/.config/quickshell/ii/`; runtime helpers must live there, not in the
repository-level `scripts/`.

```
settings.qml                         window, IPC handler, harness contract
modules/settings/
  core/        SettingsRegistry, SettingsStore (singletons), pure logic (JS)
  backends/    <Name>Backend.qml, one per persistence/apply mechanism
  components/  rows, sections, page, navigation, search, confirm bar
  pages/       <Name>Page.qml, one per page id
  registry/    pages.json, <pageId>.json, retired.json
scripts/settings/                    idlegen.py, monitorsgen.py, default-apps.py, hyprlock-time.py, open-settings.sh
```

## Pages and groups

`modules/settings/registry/pages.json` defines the navigation:

| Group | Pages |
|---|---|
| `personalization` | `quick`, `appearance`, `background`, `bar`, `panels` |
| `desktop` | `windows`, `animations`, `input`, `displays` |
| `system` | `sound`, `power`, `notifications`, `apps`, `region` |
| `tools` | `capture`, `search`, `services` |
| footer | `advanced`, `about` |

Each page id has `registry/<id>.json` and `pages/<Id>Page.qml`.

Sections per page, in order (the registry files are authoritative; the last
column counts entries, including actions and read-only rows; sections without
visible entries stay hidden, as most `animations` sections do until their
entries land):

| Page | Title | Sections | Entries |
|---|---|---|---|
| `quick` | Quick settings | Look, Bar, System | 0 + 10 aliases |
| `appearance` | Appearance | Color, Transparency, Typography, Colors from the wallpaper, Shell windows | 26 |
| `background` | Wallpaper and widgets | Wallpaper, Parallax, Clock, Cookie clock, Digital clock, Quote, Weather widget | 39 |
| `bar` | Bar | Layout, Auto-hide, Workspaces, Buttons, Indicators and tooltips, Resources, Weather, System tray | 34 |
| `panels` | Panels and overlays | Right sidebar, Open from screen corners, Dock, Overview, Overlay, On-screen display, On-screen keyboard, Shortcut cheat sheet, Media | 48 |
| `windows` | Windows and effects | Game Mode, Spacing and borders, Blur, Shadows, Dimming, Opacity, Behavior, Gestures, Window rules | 32 |
| `animations` | Animations | What each part controls, General, Windows, Workspaces, Shell panels, Details, My curves, Motion inside the shell | 6 |
| `input` | Keyboard and input | Keyboard, Mouse and pointer, Touchpad, Scrolling in the shell, Keyboard shortcuts | 21 |
| `displays` | Displays and night light | Displays, Night light, Anti-flashbang | 8 |
| `sound` | Sound | Devices, Hearing protection, System sounds | 8 |
| `power` | Power and lock | Power profile, Battery, When idle, Lock screen, Lock screen style | 21 |
| `notifications` | Notifications | Behavior, Placement, Other notification services | 6 |
| `apps` | Applications | Default applications, Shell commands, Hyprland variables | 26 |
| `region` | Language and region | Language, Time, Date | 8 |
| `capture` | Capture and recording | Screenshots, Image search, Region selector, Recording controls, Screen recording | 28 |
| `search` | Search | Launcher, Prefixes, Web search | 13 |
| `services` | Services | Weather, System updates, Resources, Music recognition, Pomodoro, AI quotas and accounts | 17 |
| `advanced` | Advanced | Configuration file, Workarounds, Work safety, Diagnostics, Reset | 14 |
| `about` | About | Distro, Dotfiles | 2 |

## Registry schema

`registry/<id>.json` is plain JSON (no comments) read by QML and Python:

```json
{
  "id": "bar",
  "title": "Bar",
  "icon": "toast",
  "description": "Position, layout and modules of the bar.",
  "sections": [
    { "id": "layout", "title": "Layout", "icon": "dashboard", "description": "Optional." }
  ],
  "entries": [
    {
      "key": "bar.bottom",
      "section": "layout",
      "label": "Bar at the bottom",
      "description": "Place the bar on the bottom edge instead of the top.",
      "keywords": ["position", "posición", "abajo"],
      "icon": "vertical_align_bottom",
      "backend": "config",
      "type": "bool",
      "consumers": ["modules/ii/bar/Bar.qml"]
    }
  ]
}
```

Entry fields:

| Field | Meaning |
|---|---|
| `key` | Globally unique id. For `config` it is the config path. Other backends use a prefix: `hyprland.<lua path>`, `animation.<x>`, `display.<field>`, `mime.<role>`, `audio.<x>`, `power.<x>`, `ipc.<x>`, `action.<page>.<name>`, `info.<page>.<name>`. |
| `section` | Section id of the same page. |
| `label`, `description` | English source strings, translated with `Translation.tr`. Description is one sentence. |
| `note` | Optional English hint shown in italics under the description. Do not use it for what a chip already says. |
| `help` | Optional English longer explanation (1–3 sentences: what it does, when to use it, what to watch out for); never repeats the description. Rendered as a "?" toggle after the label (keyboard focusable, accessible name "Help: <label>") that opens the text inline in the row, collapsed by default; it stays open for the session (per key) and opens by itself when a search result matched only through the help. |
| `applies` | Optional: when a change takes effect, shown as a chip on the label line. One of `newWindows` ("New windows only"), `nextStart` ("When the shell restarts"), `nextLogin` ("At next login"), `confirm` ("Asks for confirmation"), `onSave` ("When saved"). Instant changes have none. `risky` entries always show `confirm` too, since they always ask (`risky` with `applies: "nextStart"` shows both, `confirm` first). |
| `cost` | Optional resource the setting costs while on, shown as a chip: `gpu` ("Uses more GPU") or `battery` ("Uses battery"). |
| `minLabel`, `maxLabel` | Optional English captions for the two ends of a slider without a unit ("Subtle" … "Strong"), shown under the track (slider rows only). |
| `keywords` | Optional extra search terms (any language). |
| `icon` | Optional Material Symbols name. |
| `backend` | `config`, `hyprland`, `animation`, `idle`, `display`, `mime`, `audio`, `power`, `ipc`, `action`, `readonly`. |
| `path` | Backend address. Defaults to `key` for `config`. Hyprland: Lua path such as `input.touchpad.tap_to_click`. |
| `option` | Hyprland only: `hyprctl getoption` name, such as `input:touchpad:tap-to-click`. Lua keys use `_`, option names may use `-`. |
| `type` | `bool`, `int`, `real`, `enum`, `string`, `path`, `font`, `color`, `list`, `time`, `url`, `action`, `info`, `custom`. |
| `widget` | Optional rendering hint: `switch`, `slider`, `spin`, `segmented`, `select`, `text`, `textarea`, `path`, `font`, `color`, `list`, `time`, `device`, `action`, `info`, `custom`, `animation`, `animationPreset`, `curveLibrary`, `banner`. A widget without a row file in `SettingsPage.rowSources` renders as `SettingsCustomRow`. `banner` (for `readonly`/`info` notices such as "Game Mode is on") renders `SettingsBannerRow`: a tinted notice with the icon, label and description. |
| `min`, `max`, `step`, `unit`, `uiScale`, `decimals` | Numeric range and display. `uiScale` multiplies the stored value for display (0.5 shown as 50 with `unit: "%"`); `min`/`max`/`step` stay in stored units. Spin boxes round the displayed value and write it divided back and rounded (seconds shown as minutes with `uiScale: 1/60`). |
| `options` | Enum values: `[{ "value": <json>, "label": "English", "icon": "optional", "description": "Optional English sentence" }]`; no other option fields. Select and segmented rows show the selected option's description as "Now: <description>" in the text column. |
| `validate` | `{ "regex": "...", "maxLength": n, "nonEmpty": true, "unique": "<group>" }`. |
| `enabledWhen`, `visibleWhen` | Conditions, below. While another setting's value disables a row, the row shows a "Requires …" chip (below); a row whose `enabledWhen` or `visibleWhen` names another row of its own section is indented under it with a guide line. |
| `risky` | Needs the 15 s keep-or-revert confirmation. |
| `action` | For `type: "action"`: handler name provided by the page. |
| `consumers` | Files (relative to `config/quickshell/ii`, or repo-relative when starting with `config/`/`scripts/`) that read the setting. Required for `config`; each must contain the leaf key name. |
| `external` | Optional script that consumes the value. |
| `keys` | For composite/custom widgets: every config path they write. |
| `actionLabel`, `actionIcon`, `actionKind` | `action` rows: English button text (default "Open"), icon and `SettingsButton` kind (`tonal`, `filled`, `danger`, `text`). |
| `placeholder` | Text rows: English placeholder. |
| `pick` | Path rows: `"folder"` (default) or `"file"` for the picker button. |

A page object may also carry `iconRotation` (degrees, for example `bar`).
Unknown entry fields are rejected by the contract test. An `applies` or
`cost` value outside its list skips the entry with a `loadErrors` message, like
an unknown backend, type or widget. `help`, `minLabel`, `maxLabel` and option
descriptions are translated like labels (`es_MX` is required).

Aliases repeat a setting whose canonical home is another page (the Quick
page does this). An alias entry is exactly `{ "ref": "<canonical key>",
"section": "<section id of this page>" }`; everything else comes from the
canonical entry. The registry lists it as a copy of the canonical entry with
this page's `section`, plus `aliasOf` (canonical key) and `homePageId`
(canonical page); canonical entries have `aliasOf: ""` and `homePageId` equal
to their own page. The key stays canonical, so the store, the modified state,
reset and `objectName: "row:" + key` behave exactly like the canonical row,
and the row shows a subtle "Also in <Page>" hint. Search never returns
aliases. A ref must target an existing, non-alias entry on another page whose
path is not retired or managed elsewhere, a page may not hold two refs to the
same key, and refs do not count for key uniqueness. Invalid refs are dropped
with a `loadErrors` message.

Conditions:

```json
{ "key": "bar.autoHide.enable", "equals": true }
{ "key": "appearance.transparency.automatic", "notEquals": true }
{ "key": "bar.cornerStyle", "in": [0, 1] }
{ "capability": "battery" }
{ "all": [ … ] }  { "any": [ … ] }  { "not": { … } }
```

Capabilities are published by backends (for example `battery`, `touchpad`,
`multiMonitor`, `gameMode`; `satty` and `checkupdates` come from the `system` backend,
`ipc:<target>` from the `ipc` backend). An entry whose backend is not
available renders disabled with the backend's `unavailableReason`. An entry
disabled by a missing capability shows `capabilityReason(name)` from
`core/SettingsLogic.js` ("Requires satty, which is not installed", "No
touchpad detected", `animationsLoaded`, `vrr`, …); a capability used in `enabledWhen` needs its own text
there (contract test), while `visibleWhen` simply hides the row.

`registry/retired.json` lists config paths or prefixes of retired features.
They stay in the schema (inert, so old config files keep loading) but may not
appear in any registry entry or settings page. Retired: `policies.ai`, `ai`, `sidebar.ai`, `sidebar.translator`, `language.translator`, `sidebar.booru`, `bar.utilButtons.showScreenSnip`, `bar.utilButtons.showColorPicker`, `bar.utilButtons.showPerformanceProfileToggle`, `bar.utilButtons.showScreenRecord`, `bar.utilButtons.showTaskKiller`, `bar.workspaces.showNumberDelay`, `bar.resources.alwaysShowSwap`, `bar.resources.alwaysShowCpu`, `background.widgets.clock.cookie.dateInClock`, `calendar.locale`, `panelFamily`, `waffles`
(the AI chat, translator and booru sidebars, removed bar buttons, the old
workspace number delay, the cookie clock date, the calendar locale and the
panel family switch).
`managedElsewhere` lists `{ "path", "reason" }` for paths owned by something
other than Settings (switchwall.sh, dragging widgets, the sidebar); they are
never exposed either. Every leaf of `ConfigOptions.qml` must be registered on
a page, retired or managed elsewhere (`tests/test_settings_contract.py`).

## SettingsRegistry (`qs.modules.settings.core`)

Loads `registry/pages.json`, every `registry/<id>.json` and
`registry/retired.json` synchronously at startup (one blocking `FileView` per
file). A missing or malformed page file renders as an empty page and is
reported once in `loadErrors` (and `console.warn`); invalid entries, sections
and aliases are skipped the same way, so they never break other pages.

| Member | Meaning |
|---|---|
| `ready`, `loadErrors` | Loaded flag; list of English problem strings. |
| `groups` | `[{ id, title, pages: [page] }]` in navigation order. |
| `pages` | Every page object, groups first, then footer pages. |
| `footerPages` | `advanced`, `about`. |
| `retired` | Parsed `retired.json` (`retired`, `managedElsewhere`). |
| `page(id)` | `{ id, group, title, icon, iconRotation, description, source, sections, entries, broken }`; `source` is `modules/settings/pages/<Id>Page.qml`. |
| `entry(key)` | Canonical entry (normalized: `pageId`, `homePageId`, `aliasOf: ""`, `path` defaulted to `key`, `widget` defaulted from `type`, `risky` bool). A key listed in a custom entry's `keys` resolves to a minimal `type: "custom"` entry owned by it. |
| `allEntries()` | Canonical entries of every page. |
| `homePageId(key)` | Page that owns a key. |
| `entriesForPage(id)` | Entries shown on a page, aliases included (resolved). |
| `sections(pageId)`, `section(pageId, id)`, `entriesForSection(pageId, sectionId)` | Lookups. |
| `isRetired(path)` | Path equals or is under a retired prefix. |
| `search(query, limit = 20)` | Ranked results, below. |

Default widgets: `bool` switch; `int` slider when its range has more than 20
steps, else spin; `real` slider; `enum` segmented with up to 3 options, else
select; `string`/`url` text; other types map to the widget of the same name.
`spin` is integer-only: use a slider for reals.

Search folds case and diacritics (`normalize("NFD")` and stripping
`̀-ͯ`) on both sides and matches translated and English labels,
descriptions, keywords, section and page titles. "atenuación" and
"atenuacion" find the same rows. Results carry `kind` (`page`, `section`,
`entry`), `pageId`, `sectionId`, `key` and a score. Every query word must
match; per word, label prefix (100) > word prefix inside the label (80) >
label substring (60) > keyword (50) > section/page title (40) > description or
note (20); a label starting with or equal to the whole query gets a bonus.
Ties: settings, then pages, then sections, then registry order.

## SettingsStore (`qs.modules.settings.core`)

| Member | Contract |
|---|---|
| `value(key)` | Effective value. Reads `Config.options` for `config` (so bindings track the exact property) or the backend's `values`. |
| `defaultValue(key)` | `Config.defaults` for `config`; backend-defined otherwise. |
| `isModified(key)` | Value differs from the default (deep compare), or the backend holds an override (Hyprland). |
| `isAvailable(key)`, `unavailableReason(key)` | Backend availability and capabilities. |
| `write(key, value)` | Validates and coerces to the entry type, then routes to the backend. Returns `false` and emits `failed` when rejected. Risky entries are previewed and opened for confirmation instead of persisted. |
| `reset(key)`, `resetPage(pageId)` | Back to the default (Hyprland: remove the override). `resetPage` skips rows hidden by `visibleWhen`. |
| `modifiedCount(pageId)` | Visible rows of the page with at least one modified key ("Reset page" shows when > 0). |
| `pendingConfirmation` | `null` or `{ keys, secondsLeft }`. Further risky writes join the batch and restart the countdown. |
| `confirm()`, `revert()` | Persist or restore the batch. Timeout and window close revert. |
| `finish(done)`, `cancelFinish()` | Before quitting: revert a pending batch, call each backend's `flush()` and call `done` once no backend is `busy` (at most 10 s, then a warning). `cancelFinish()` keeps the session (the window was opened again). |
| `revision` | Increments whenever any backend value changes. |
| `committed(key)`, `failed(key, message)` | Outcome signals. `message` is an English source string; translate it with `Translation.tr`. |
| `entry(key)` | Same as `SettingsRegistry.entry`. |
| `isEnabled(key)`, `isVisible(key)` | Availability plus `enabledWhen`; `visibleWhen`. |
| `blockingCondition(key)` | First failing leaf of `enabledWhen` (`{ key, … }` or `{ capability }`), or `null`. |
| `hasCapability(name)` | Any available backend lists the capability. |
| `choices(key)` | `backend.choices(entry)` when the backend implements it (devices, applications), else `entry.options`. |

Validation and coercion (`core/SettingsLogic.js`): `int` rounds and clamps,
`real` clamps (and rounds to `decimals`), `enum` must equal one option value
(type-exact), text types accept strings or numbers and keep them as strings,
`color` is empty or `#RRGGBB[AA]`, `time` is `HH:MM`, `list` is a list of
strings, `validate` applies `regex`, `maxLength`, `nonEmpty` (per item for
lists) and `unique` (no other entry of the group holds the same value).
Writing the current value is a no-op. Entries of the `action` and `readonly`
backends, and `action`/`info` types, are never written.

Risky batch: the first risky write snapshots each entry once, calls
`preview()` and opens `pendingConfirmation`. Before that first preview the
store sets `deferWrites = true` on every backend that declares the property,
and sets it back to `false` after `persist()`/`restore()` in `confirm()` and
`revert()` (also on timeout and window close); such a backend queues its
normal writes meanwhile and flushes them when it drops to `false`.
`reset(key)` of a risky entry calls `backend.previewReset(entry)` when the
backend implements it (the reset value is unknown up front, as when Hyprland
drops an override) and joins the batch like a preview; otherwise it writes
`defaultValue(key)` through the same risky path.

The logic is in `core/SettingsStoreImpl.qml` (QtQuick only, `registry` and
`backends` properties) so `tests/qml_settings` drives it with mock backends;
the `SettingsStore` singleton wires the real registry and one instance of
every backend.

The store never uses `Config.setNestedValue` (it coerces numeric strings);
`ConfigBackend` assigns the already-typed value to the nested property.

## Backends

Each `backends/<Name>Backend.qml` implements:

`name`, `available`, `unavailableReason`, `values` (key → effective value),
`capabilities`, `read(entry)`, `defaultValue(entry)`, `isModified(entry)`,
`write(entry, value)`, `reset(entry)`, `snapshot(entries)`,
`preview(entry, value)`, `persist(entries)`, `restore(snapshot)`, signals
`succeeded(key)` and `failed(key, message)`. Optional: `choices(entry)`
(`[{ value, label, translate }]`: labels are device or application names
shown as they are, unless `translate: true` marks them as English source
strings, as for idle timeouts and power profiles), `property bool
deferWrites`, `previewReset(entry)`, `readonly property bool busy` (work that
must finish before the app quits: queued or running writes, restores and
their commands, not reads) and `flush()` (runs debounced writes now).
`write`, `reset`, `preview`, `persist` and `restore` return `false` when they
fail synchronously; the commands they start run asynchronously. The
`SettingsStore` singleton instantiates one of each backend.

| Backend | Persistence and apply |
|---|---|
| `config` | `config.json` through `Config`; the main shell reacts through its file watch. |
| `hyprland` | `~/.config/hypr/custom/shell-settings.lua`, required by `config/hypr/hyprland.lua` after `custom/*` and `monitors.lua` and before `hyprland.shellOverrides.main` (Game Mode keeps winning while active). Effective values come from one `hyprctl -j descriptions` at start and after every `configreloaded`; an entry is modified when the file overrides it (`hyprconfigurator.py --list --json`). Normal writes coalesce for 400 ms into one `hyprconfigurator.py --set-typed/--unset` call (types from the registry, not from Hyprland's defaults); writing the file triggers Hyprland's autoreload once Hyprland watches it, which it does only after its config has loaded the file (`hyprland.lua` requires it only when it exists). A write that no `configreloaded` follows within 2 s therefore ends with one `hyprctl reload config-only` (monitors untouched), which also makes Hyprland watch a newly created file. Risky values preview with `hyprctl eval 'hl.config({...})'`, are re-applied after any reload while the confirmation lasts, and are written only on confirm. A risky reset removes the override at once (`previewReset`) and restore puts it back. While any confirmation is pending (`deferWrites`), normal file writes wait, because the reload they trigger would drop live previews. Never `hyprctl keyword`. Capabilities: `touchpad` (`hyprctl -j devices`), `gameMode` (Game Mode's line in `shellOverrides/main.lua`). Defaults and Game Mode: see "Backends -> hyprland" below. |
| `idle` | `idle.*` in `config.json`, rendered by `scripts/settings/idlegen.py --restart` into `~/.config/hypr/custom/shell-idle.conf` (sourced by `config/hypr/hypridle.conf`); hypridle reads its config only at start, so every apply restarts it (a restart forgets inhibitors that apps took through hypridle's D-Bus ScreenSaver interface until they inhibit again). Risky: the preview renders and restarts, `config.json` is written on confirm, restore renders the previous values. Nothing is written on load: a file that differs from `config.json` publishes `idleOutOfSync` ("Apply" action) and a file without the marker `idleUnmanaged` ("Replace"). |
| `display` | State from `hyprctl -j monitors all` (disabled outputs included), as a `monitorsgen.py` spec. Per-output VRR comes from the managed `monitors.lua` (`vrrFromManagedText`), not from hyprctl's `vrr`, which only says whether VRR is active right now; an output without one has `vrr: null`, is written without `vrr` and follows `misc:vrr` (a per-output value overrides it). Preview: `monitorsgen.py --lua-expr --spec-json …`, then `hyprctl eval` with that expression; `~/.config/hypr/monitors.lua` is written only on confirm, with a marker header. A file without the marker is never overwritten silently: `monitorsFileUnmanaged` offers "Replace (keeps a backup)", which uses `--force`. The last enabled output cannot be turned off. Risky. |
| `mime` | `scripts/settings/default-apps.py list --json` and `set <role> <desktop-id>` (argv). It implements the freedesktop MIME association spec directly and edits `mimeapps.list` in place, because the installed `xdg-mime` ignores `hyprland-mimeapps.list` and rejects apps whose `Exec` is quoted. A candidate must open the role's primary type; setting it claims only the types it declares. The current default may be an app that is not a candidate (hidden or `NoDisplay`), and the page still shows it. |
| `audio` | `Quickshell.Services.Pipewire` preferred default sink and source; duplicate HDMI nodes are merged. Capability `pipewire`. |
| `power` | `Quickshell.Services.UPower` power profiles (the performance profile only when offered) and the `battery` capability (`UPower.displayDevice.isLaptopBattery`). |
| `system` | No entries. Probes optional tools once at start with `which <tool>` (argv) and publishes the found ones as capabilities (`satty`, `checkupdates`), independent of the main shell. Always available. |
| `animation` | Hyprland animations and curves (keys `animation.*`) in `~/.config/hypr/custom/shell-animations.lua`, written by `scripts/settings/animationsgen.py` and applied live with one `hyprctl eval` per change; see "Backends -> animation" below. |
| `ipc` | `qs -p <shell dir> ipc call …` to the main shell, which is the same instance as `qs -c ii` (Do Not Disturb through `notifications`, AI quota connect through `aiQuotaPanel.connectProvider`, region recording through `region`). Available while `ipc show` answers; polled every 10 s while the app is open. The app never starts `ai-quotas.py serve` itself. |

Helper scripts (`scripts/settings/`, run as `python3 <script>` with argv;
exit 0 ok, 1 I/O error, 2 invalid input unless noted):

| Script | Interface |
|---|---|
| `idlegen.py` | `[--lock S] [--dpms S] [--suspend S] [--output PATH] [--force] [--print] [--restart]`. Seconds, 0 = never, otherwise 30–86400 with lock ≤ dpms ≤ suspend. Exit 3: target without the marker (needs `--force`); exit 4: hypridle could not be restarted (`systemctl --user restart` when the unit is active, otherwise `pkill -x hypridle` and a new instance started through Hyprland with `hyprctl eval 'hl.exec_cmd("hypridle")'`, so it gets the session's environment and scope rather than the app's; detached directly when Hyprland is not running or did not start it). |
| `monitorsgen.py` | `[--output PATH] [--force] [--print \| --lua-expr [--name OUTPUT]] [--spec-json TEXT]`; the spec (`{"monitors": [...]}`) comes from `--spec-json` or stdin. `--force` backs up an unmanaged file to `<name>.bak-YYYYmmdd-HHMMSS`. Exit 3: unmanaged target. |
| `default-apps.py` | `list [--json]`, `set ROLE DESKTOP_ID`; roles `browser`, `fileManager`, `mail`, `image`, `video`, `audio`, `text`, `pdf`. |
| `hyprlock-time.py` | `24h\|12h [--file PATH]`: switches `$TIME`/`$TIME12` in `hyprlock.conf` atomically; a missing file is not an error. |
| `open-settings.sh` | `[pageId [settingKey]]`: single instance; forwards to `settingsApp.open`/`reveal` (`show` without arguments, best effort) over IPC and focuses the window, or starts the app with `II_SETTINGS_PAGE`/`II_SETTINGS_KEY`. |

`scripts/hyprland/hyprconfigurator.py --file PATH` takes `--set KEY VALUE`
(legacy typing), `--set-typed KEY bool|int|float|string VALUE`,
`--reset/--unset KEY`, `--header TEXT` (only for a new or empty file) and
`--list --json`. Keys use `:` between Lua identifiers; control characters are
rejected and an unchanged file is not rewritten.

Hyprland facts verified on 0.57: `hyprctl eval` prints `ok` with exit 0;
unknown keys fail with exit 7 (`unknown config key 'input.x'`); empty strings
are accepted (`kb_variant = ""`); `hyprctl -j descriptions` lists every option
with default, current value, range and enum map (no type: the registry
declares it); `getoption` returns `[[EMPTY]]` for unset strings and
`"css": "4 4 4 4"` for gaps. `hl.config` takes gaps as an integer (or a table),
not as the CSS string (`gaps_in = "4 4 4 4"` fails with exit 7), so the app
writes one integer for every side.

### Backends -> hyprland

**Defaults.** `defaultValue(entry)` is what a reset leaves in place: the
dotfiles' own value (the "base") when they set the option, Hyprland's compiled
default (`hyprctl -j descriptions`) when the base was read and nothing in the
dotfiles sets it, and `undefined` (unknown: rows hide the default mark and the
"Reset to X" text) when the base could not be read or is not read yet. The
base comes from `scripts/settings/hyprbase.py --json --config-dir
<config>/hypr`, run at start and, debounced by 300 ms, after every
`configreloaded`. A failed read is an expected state and logs nothing. The
whole parsed result (`config`, `curves`, `animations`) is also published as
`basePayload`, which `SettingsStore` passes to the `animation` backend as
`sharedBase`, so the dotfiles run once per reload for both backends.

**Game Mode.** While Game Mode's line is in `shellOverrides/main.lua`
(capability `gameMode`), the backend lists that file with
`hyprconfigurator.py --list --json --file <main.lua>` (Game Mode's keys are
never hardcoded). For each option listed there, `read()` returns the stored
value (the `shell-settings.lua` override, else the base, else the compiled
default) instead of Hyprland's live value, and `statusNote(entry)` returns
"Paused by Game Mode" ("" for every other option). Rows that depend on such
an option (for example `enabledWhen` on `hyprland.animations.enabled`) are
therefore not disabled by Game Mode. Writes and resets of those options go to
`shell-settings.lua` as usual and apply when Game Mode ends, because
`shellOverrides/main.lua` loads last; they are never evaluated live. A risky
preview of such an option is not applied live either: `preview()` holds the
value, `persist()` writes it and `restore()` drops it without `hyprctl eval`.
The pause is checked again when a live preview is re-applied after a reload
and on restore, so Game Mode starting during a confirmation keeps its live
value too. A `configreloaded` re-applies the previews only after Game Mode's
file and overrides have been read again, so the reload Game Mode's own start
triggers does not re-apply them with the overrides from before it. Optimistic values work as for any other write.

**`hyprbase.py`.** `python3 scripts/settings/hyprbase.py --json [--config-dir
DIR] [--options FILE]` (default `DIR`: `$XDG_CONFIG_HOME/hypr`, else
`~/.config/hypr`) runs `DIR/hyprland.lua` with `/usr/bin/lua -E` and a stub
`hl` and prints one JSON object, also on failure:
`{"ok", "errors", "config", "curves", "animations"}`. `config` maps getoption
names to the literal values passed to `hl.config` (booleans, strings and
finite numbers: NaN and infinities such as `0/0` are noted in `errors` and
ignored, so an earlier value stays; nested tables flattened
with `:`, and `.` after `col`: `general:col.active_border`; arrays such as
`decoration:shadow:offset` stay arrays). `curves` holds `hl.curve` calls
(beziers as `{"type": "bezier", "points": [x1, y1, x2, y2]}`, springs with
`mass`, `stiffness`, `damping`); `animations` holds `hl.animation` calls by
leaf (`enabled`, `speed`, `bezier` or `spring`, `style`, as passed). Later
calls override earlier ones. `custom.shell-settings`,
`custom.shell-animations` and `hyprland.shellOverrides.main` are skipped;
`custom/*` is part of the base. Every other `hl.*` field is a no-op, so
`hl.on` callbacks never run. Sandbox: `require` resolves `a.b` (or `a/b`)
only to `DIR/a/b.lua` or `DIR/a/b/init.lua` (a missing module is noted in
`errors`, not fatal); `io.open` is read-only and confined to `DIR`, with
`$HOME/.config/hypr/...` mapped into `DIR`; `os.getenv` answers only `HOME`
and `XDG_CONFIG_HOME`, consistent with that mapping; `os.execute`,
`io.popen`, `os.remove`, `os.rename`, `os.exit`, `io.write`, `load`,
`loadfile` and `dofile` are blocked and noted in `errors`; `getmetatable`
returns nil for strings and file handles, whose metatables are shared with the
sandbox's own code; the process gets
`RLIMIT_FSIZE` 0, a CPU and memory limit and a 5 s timeout. `--options FILE`
(an object keyed by getoption name, as `tests/fixtures/hyprland-options.json`,
or the `hyprctl -j descriptions` list) adds `unknown option '<name>'` to
`errors` for names Hyprland does not know. Exit 0 with `ok: true`; exit 1
with `ok: false` (missing `hyprland.lua`, Lua syntax or runtime error,
timeout) and empty `config`/`curves`/`animations`; exit 2 for invalid
arguments.

Tests: `tests/test_hyprbase.py` (the repository's `config/hypr`, skipped
files, sandbox, non-finite numbers, CPU limit and wall-clock timeout (a read
of a FIFO), `RLIMIT_FSIZE` and that `read_base` applies the limits, schema of `tests/fixtures/hyprbase-sample.json`),
`tst_HyprlandLogic.qml` (`defaultFor`, `storedValue`, `isPausedByGameMode`,
`parseBase`) and `tests/test_hyprland_base.py`, which runs
`tests/harness/drivers/hyprland-base.qml` with `--hyprland-stub` and a
descriptions fixture standing for Game Mode's live values. The driver also
checks that `succeeded(key)` fires when only a row's default changes (the base
arrives after the first read) or only its status note (Game Mode starts or
ends with the app open): rows learn about changes only through that signal.
It also checks that, after a write and the reload that drops its optimistic
value, `read()` returns the `shell-settings.lua` override while Game Mode's
live value stays, and that a preview made before Game Mode started is not
evaluated again on a reload or on restore while Game Mode overrides it.

### Backends -> animation

`backends/AnimationBackend.qml` (pure logic in `backends/AnimationLogic.js`)
manages 10 animation cards, the derived preset and the user's curves.
Verified Hyprland 0.57 behaviour it relies on is in the plan's evidence
(live spikes A1–F2) and in the tests named below.

**Keys.** The card id is the entry `path` (`animation.` prefix optional).

| Key | Value |
|---|---|
| `animation.<card>` | `{ enabled, speed, curve, style }` for `windowsIn`, `windowsOut`, `windowsMove`, `workspaces`, `specialWorkspaceIn`, `specialWorkspaceOut`, `layersIn`, `layersOut`, `border`, `zoomFactor`. `speed` is Hyprland's, in deciseconds (1 = 100 ms; accepted in (0, 100]); `curve` a curve name; `style` a style of the card's family ("" = none). |
| `animation.preset` | `default`, `agile`, `smooth`, `bouncy`, `minimal`, or the read-only `custom`. Derived from the cards, never stored; `isModified` is always false. |
| `animation.curves` | The user's curves: `[{ name, type, points \| mass/stiffness/damping, label, group: "user", builtin: false }]`. A write replaces the whole list (added, changed and removed curves in one change). `isModified` is always false, so "Reset page" never deletes curves. |

Windows and layers cards also write their fade companion (`fadeIn`,
`fadeOut`, `fadeLayersIn`, `fadeLayersOut`): same `enabled`, speed
`clamp(round2(base_c × speed / base_p), 0.01, 100)` from the dotfiles base
speeds (`round2(x) = floor(x × 100 + 0.5) / 100` on both sides), base curve,
no style; with a spring the companion keeps its base speed. Styles allowed per
family: windows `slide [top|bottom|left|right]`, `popin [N%]`, `gnomed`;
workspaces `slide`, `slidevert`, `fade`, `slidefade [N%]`,
`slidefadevert [N%]`; layers `fade`, `slide [dir]`, `popin [N%]`; border and
zoom none (N is 0–100). Curves: Hyprland's `default` and `linear`, the
dotfiles curves of the base, the app springs `ii_spring_soft` and
`ii_spring_bouncy`, and user curves named `ii_[a-z0-9_]{1,32}` (bezier with
x in [0, 1] and y in [-1, 2]; spring values in (0.5, 10000]; label 1–40 code
points without control characters).

**Values.** A card shows, in order: its line in the generated file (the source
of truth: Hyprland forgets speed and curve of a disabled leaf and rounds
`hyprctl -j animations`), the dotfiles base (`scripts/settings/hyprbase.py
--json`, read once by the `hyprland` backend and passed in as
`sharedBase`; the nearest overridden ancestor in Hyprland's animation tree) and Hyprland's compiled default (`global`: enabled, speed 8,
curve `default`). `defaultValue` is the base value, or `undefined` while the
base is unknown. A card is modified while the file holds its line. Without the
base, cards and curves stay readable, but card and preset writes (other than
`default`) fail with a message, since companions and presets need it. Rows
learn about changes only through `succeeded(key)`: the backend emits it for
every read key whose value, modified state, default or status note changed
outside a write (the base arriving, Game Mode starting or ending, a reload).

**Generated file.** `~/.config/hypr/custom/shell-animations.lua`
(`$XDG_CONFIG_HOME` honoured), required by `config/hypr/hyprland.lua` with
`pcall(require, "custom.shell-animations")` after `custom.shell-settings` and
before the shell overrides, so Game Mode keeps winning and a broken file does
not stop it (Hyprland 0.57 records the error in its config errors and runs
the rest; `tests/test_animations_hyprland_verify.py`). Layout:

```lua
-- managed by the settings app (scripts/settings/animationsgen.py); manual edits are overwritten
-- Generated file: Hyprland animations and curves chosen in the settings app (loaded by hyprland.lua).

-- ii:curve {"label": "My curve", "name": "ii_my_curve"}
hl.curve("ii_my_curve", { type = "bezier", points = { { 0.2, 0 }, { 0, 1 } } })
hl.curve("ii_spring_soft", { type = "spring", mass = 1, stiffness = 238.1191, damping = 24.21279333 })

hl.animation({ leaf = "windowsIn", enabled = true, speed = 2, spring = "ii_spring_soft", style = "popin 85%" })
hl.animation({ leaf = "fadeIn", enabled = true, speed = 3, bezier = "emphasizedDecel" })
hl.animation({ leaf = "border", enabled = false, speed = 6, bezier = "ii_my_curve" })
```

User curves are always written, app springs only while a card uses them, and
every `hl.curve` comes before the first `hl.animation`. Labels live in
`-- ii:curve` comments as ASCII-escaped JSON. A disabled card keeps its full
tuple (Hyprland accepts and ignores the extra fields), so enabling it again
restores it. Numbers never use an exponent.

**`animationsgen.py`** (python3 stdlib, argv only, the app's only Lua
serializer): `[--file PATH] --list --json` prints `{ ok, exists, cards,
leaves, curves, appCurves, errors }`; `[--file PATH] --apply-json FILE|-
[--eval]` takes `{ "cards": { card: value | null }, "curves": { name:
descriptor | null }, "removeAllAnimations": bool, "base": <hyprbase JSON> }`
(curves first, then `removeAllAnimations`, then cards; `null` removes a card's
lines or deletes a user curve) and prints one `{ ok, changed, written, evalOk,
reloaded, errors, cards }`. Every emitted value is re-validated (names
`^[A-Za-z_][A-Za-z0-9_]*$` and known, styles from the allowlist, finite
numbers in range), carried-over lines too. A dotfiles curve in `base` whose
name is not a Lua identifier, or whose `type` is missing or unknown (Hyprland
0.57 reports and skips it), is left out (reported in `errors`, also on
success), and so is a base animation that uses such a curve, an enabled one
without a speed (`hyprbase.py` drops a non-finite speed such as
`speed = 1/0`) or one with a numeric `enabled` other than 0 or 1 (Hyprland
reads `enabled = 0` / `1` as false / true and rejects other numbers); its
parent or Hyprland's compiled tuple applies, instead of rejecting the whole
base; any other malformed curve or animation still rejects it.
`AnimationLogic.js` (`resolveLeaf`, `curveCatalog`) resolves the base by the
same rules (the "bases" cases of `tests/fixtures/animation-cases.json`). Deleting a curve a card uses fails
naming the cards; deleting a Hyprland, dotfiles or app curve fails. Card
writes need `base`. With `--eval`, the new or changed statements (curves
first) go to one `hyprctl eval` before the write; removed lines are applied by
the reload that follows the write. Unchanged content is not written (no eval,
`changed: false`). Exit codes: 0 ok; 2 usage or validation error (nothing
applied or written); 3 the file is not ours (no marker, or not a regular
file: never overwritten); 4 `hyprctl eval` failed, `hyprctl reload
config-only` already ran and nothing was written; 5 the file could not be read
or written.

**Writes.** `write` validates with `AnimationLogic` (the same cases as the
generator: `tests/fixtures/animation-cases.json`), shows the value at once and
queues it; after 400 ms one `animationsgen.py --apply-json - --eval` runs
(serial queue, change set on stdin). A value equal to the shown one starts
nothing. The change stays shown until a `--list` that started after the
generator finished; a list started earlier (by a `configreloaded` while the
generator runs) still sees the old file and keeps it. A preset writes the 10 cards in one change set (one generator call,
one eval, at most one reload); `default` sends `removeAllAnimations` and keeps
the curves. Results:

- changed: when Hyprland does not answer with `configreloaded` within
  `reloadGraceMs` (2 s), one `hyprctl reload config-only` runs (Hyprland only
  watches the file once its config loaded it);
- unchanged: nothing else;
- any failure: exit 4 was already compensated by the generator; for any other
  exit the backend runs `hyprctl reload config-only` (an eval may have applied
  part of the batch). Then the optimistic value is dropped, the managed state
  is read again and `failed(key, message)` carries
  "Could not apply the animation: <generator error>" (already translated).

`deferWrites`, `busy` and `flush()` behave as in the `hyprland` backend.
Entries are never risky (`preview` returns false; `snapshot`/`restore` exist
for the contract).

**Availability and capability.** Available while Hyprland runs
(`HYPRLAND_INSTANCE_SIGNATURE`) and `--list` succeeded; a file without the
marker makes it unavailable ("custom/shell-animations.lua was not created by
Settings, so it is left alone"). The capability `animationsLoaded` is
published while the deployed `hyprland.lua` requires `custom.shell-animations`
(checked with a regex after Lua comments are stripped, so a commented-out
require does not count; refreshed on `configreloaded`). After the first changed
write and its reload, the backend reads `hyprctl -j animations` once, waiting
until no write is queued, running or awaiting its reload, and compares the
primary leaves of the latest changed write (speed at 2 decimals, `spring:<name>`
for springs); on a difference it drops the capability and emits `failed`
("Hyprland did not load the animation settings: update hyprland.lua"). A
read that fails or does not parse proves nothing: the check runs again after
the next reload.

**Game Mode.** Watched like the `hyprland` backend (`shellOverrides/main.lua`,
`HyprlandLogic.isGameModeActive`). Game Mode only sets `animations:enabled`, so
cards keep showing and writing their stored values; `statusNote(entry)`
returns "Paused by Game Mode" for cards and the preset while it is on.

**UI helpers.** `curveCatalog()` (`[{ name, type, points | spring values,
label, group: "hyprland" | "dotfiles" | "app" | "user", builtin }]`, labels
are English source strings; dotfiles curves without a friendly name use their
identifier), `styleOptions(card)` (`[{ kind, label, description, percent,
directions }]`; descriptions depend on the card's family, because a
workspace style moves the whole workspace and offers no side), `presets()` (`[{ value, label, description }]`),
`curveUsage(name)` (card ids using a curve; a used curve cannot be deleted)
and `summaryParts(card)` (`{ enabled, style: { kind, label, percent,
direction, known, raw } | null, durationMs (null for springs), spring, curve:
{ name, label, known } }`, to be translated and joined by the page;
`popin 100%` is labelled "Fade only", unknown styles and curves "Not
recognized: %1" with the raw text kept). `AnimationLogic.parseStyle(card,
style)` / `formatStyle(card, parsed)` convert styles; an unknown style is
kept as it is (`known: false`).

**Tests.** `tests/test_animationsgen.py` (generator, parity cases, `--eval`
with the harness `hyprctl` stub, and `tst_AnimationLogic.qml` run with
`QML_XHR_ALLOW_FILE_READ=1` so its fixture-driven parity test runs instead of
skipping), `tests/test_animations_hyprland_verify.py` (`Hyprland
--verify-config` of every preset, all-disabled cards, user curves and both
springs, every allowlisted style, and a broken file inside the `pcall`;
skipped when Hyprland is missing; the `pcall` itself is checked in the text of
the loader block, since Hyprland 0.57 continues after a failing require either
way), `tests/qml_settings/tst_AnimationLogic.qml`
and `tests/test_animation_backend.py` (driver
`tests/harness/drivers/animation-backend.qml` with the `hyprctl` stub behind a
wrapper that can fail one `-j animations` read, the `python3` shim of
`tests/harness/stubs/` (it can fail or delay one generator call) and the base
from `tests/fixtures/hyprbase-sample.json` through the `baseFixture` test
seam; the driver also covers a reload while the generator runs, the base
arriving late, Game Mode notes announced, a failed confirmation read, a
`hyprland.lua` without the require, a write queued during an apply that waits
for a fresh read of the file, and the base fixture going missing).
Style texts (`STYLE_DESCRIPTIONS`) follow Hyprland 0.57: a window's style is
read only when it opens or closes (so the `windowsMove` card's styles say a
move ignores them), and a special workspace always fades as well.

## Rows and pages

All components use implicit sizes only: no `width:`/`height:` on items, except
a line ending in `// size-ok: <reason>` for an item outside layouts. Tooltips
appear only on hover (`StyledToolTip` needs `parent.hovered === true` or
`alternativeVisibleCondition`). A freshly loaded page has no open popup.

`SettingsRow` (base, an `Item`):

| Member | Meaning |
|---|---|
| `settingKey` | Canonical key; `objectName: "row:" + settingKey`. |
| `listedEntry` | Entry as listed by the page (alias copies carry `aliasOf`/`homePageId`). |
| `entry`, `page` | Canonical entry; the rendering `SettingsPage` (for `actions`, `customDelegates`, `infoValues`). |
| `label`, `description`, `note`, `iconName` | Translated registry texts. |
| `value`, `defaultValue`, `modified`, `writable` | From the store (track `revision`). |
| `rowEnabled`, `disabledReason` | `isEnabled` plus `extraEnabled`; the reason line shows the backend reason or the capability's reason. A row disabled by another setting shows the `requires` chip instead of a line. |
| `available` | `SettingsStore.isAvailable`. |
| `requires` | `{ key, text }` while another setting's value disables the row (first failing leaf of `enabledWhen`), else `null`. `text` is `Logic.dependencyText`: "Requires “X”" (bool on, or a truthy leaf), "Requires “X” off" (`equals: false`, `notEquals: true`, `not`), "Requires “X”: A" or "…: A or B" (`equals`/`in` with the option labels), "Requires “X” not set to A" (`notEquals`). |
| `chips` | `Logic.rowChips(entry, requires)`: at most 2 chips on the label line, priority requires > `confirm` > `nextStart`/`nextLogin`/`newWindows`/`onSave` > `cost`. The requires chip is a link (Enter, Space or click): it scrolls to and highlights the target row on this page, or asks `SettingsSession.requestReveal(key)`, which `SettingsShell` forwards to `settings.qml` `reveal()` (another page). |
| `help`, `helpOpen`, `toggleHelp()` | Translated `entry.help`; the "?" toggle (`objectName: "helpToggle"`) and the inline text (`"helpText"`). Open state lives in `SettingsSession` for the session. |
| `optionNote` | "Now: <description>" of the selected option: select and segmented rows; device rows when the registry entry's options describe the current value (`power.profile`); the color scheme delegate (`SettingsSchemeChoice`) sets it on its custom row. |
| `statusNote` | Translated `SettingsStore.statusNote(key)`, an italic status line (`objectName: "statusNote"`, its text `"statusNoteText"`). |
| `showPlaceholder`, `needsValue`, `placeholderWhenUnavailable` | A writable row whose backend is unavailable (or, with `needsValue`, whose value is `undefined`) shows "—" (`"valuePlaceholder"`) instead of its control, never a made-up checked, unchecked or minimum value. Switch, slider, spin, select and segmented rows set `needsValue`. |
| `reasonInBanner` | The section banner already shows this row's unavailable reason, so the row has no lock line. |
| `resetText` | Reset button tooltip and accessible name: "Reset to <formatted default>" (`Logic.formatValue`: units, option labels, On/Off, percentages without decimals), "Reset to default" when the default has no short form, "Reset" when it is unknown. |
| `highlighted`, `pulse()` | Search reveal highlight. |
| `Accessible.description` | Description, help, "Now: …", chip texts, status note, disabled reason and error, translated, as one text. A row disabled by another setting says its "Requires …" sentence once (the chip), without the identical disabled reason. |
| `busy`, `errorText` | `errorText` follows `SettingsStore.failed` for this key and clears on `committed`. |
| `hovered` | `HoverHandler`. |
| `stacked`, `controlFillsWidth`, `controlPreferredWidth` | Layout: the control goes below the text when `stacked`, the row is narrower than 520 px, or the control needs more than 55% of the width. Drop-downs share `SettingsMetrics.selectWidth` so a section's controls line up; long labels elide. |
| `focusVisible` | Variants bind it to their control's `visualFocus`; draws the focus ring. |
| `commit(value)` | `SettingsStore.write`; emits `rejected()` on failure so the variant resyncs its control. |
| `resetToDefault()` | Reset button (shown only when modified and enabled). |
| `activateHandler`, `interact()` | Click on the row outside the control; `interact()` performs the primary interaction (switch flips, select/segmented move to the next option) and returns `false` when the variant has none. The harness driver uses it. |
| default children | The control, placed in a `RowLayout` on the right. |

Variants (all take `settingKey`): `SettingsSwitchRow`, `SettingsSliderRow`
(`uiScale`, `unit`, `decimals`, percentages always without decimals; the
value uses the locale's decimal separator and no group separator; writes
on release or keyboard step; under the track `minLabel`/`maxLabel` and a tick
at the default value when it is known),
`SettingsSpinRow` (integers; typed text commits on Enter/focus loss),
`SettingsSelectRow` (re-applies the selected index when its options are
rebuilt, which resets the combo box), `SettingsSegmentedRow`, `SettingsTextRow`
(Enter/focus loss commits, Esc restores), `SettingsTextAreaRow` (commits on
focus loss), `SettingsPathRow` (folder/file picker), `SettingsFontRow`
(installed families), `SettingsColorRow` (hex with swatch; empty =
automatic), `SettingsListRow` (chips plus add field), `SettingsTimeRow`
(zero-padded hour and minute spin boxes), `SettingsDeviceRow` (select over
`SettingsStore.choices`), `SettingsActionRow`, `SettingsInfoRow`,
`SettingsCustomRow`, `SettingsBannerRow` (widget `banner`; not a
`SettingsRow`: no control, `interact()` returns false, `pulse()` works). Rows
show the stored value through `Binding {
restoreMode: Binding.RestoreNone }` and write only on interaction.

`SettingsPage { pageId }` (a `StyledFlickable`) renders the header (icon,
title, description and "Reset page" with an inline confirmation, shown only
while something on the page is modified), then every section and entry in
registry order, choosing the row file by `widget`. Members:

| Member | Meaning |
|---|---|
| `customDelegates` | `{ entryKey: Component }` for `custom` entries. The delegate's root gets `row` (the `SettingsCustomRow`, for `value`/`commit`) and `entry` assigned when it declares those properties. It renders below the label at full width, or beside it like a built-in control when its root declares `inlineControl: true` (single drop-downs). |
| `actions` | `{ actionName: function(entry) }` for `action` entries; a missing handler disables the row. |
| `infoValues` | `{ entryKey: text }` shown by `info` rows (falls back to the store value). |
| `scrollTo(key)`, `scrollToSection(sectionId)` | Reveal (and for rows, pulse-highlight); return `false` when absent or hidden. |
| `sectionBannerReason(sectionId)` | English reason when every visible, writable row of the section is unavailable for the same reason (`Logic.sectionBannerReason`), else `""`. The section then shows one `SettingsBannerRow` with it at the top of its card (`objectName: "sectionBanner:<id>"`) and those rows drop their lock line. |

A page file is just `SettingsPage { pageId: "<id>"; ... }`; pages with no
entries show an empty state. Sections render as `SettingsSection`
(`sectionId`, `title`, `icon`, `description`, `bannerText`, rows as default
children, `objectName: "section:" + id`). Rows whose `enabledWhen` or
`visibleWhen` names another row of the same section (`Logic.sectionDependencies`) are indented by
`SettingsMetrics.dependentIndent` with a guide line.

`SettingsChip` (`label`, `iconName`, `interactive`, `maximumWidth`, `clicked`)
is the pill used on label lines; only interactive chips take focus. A chip
wider than `maximumWidth` (the label line) wraps to two lines; one still cut
short shows its whole text as a tooltip on hover or keyboard focus. The
modified dot and the "?" follow the end of a wrapped label's last line.
`SettingsWindowPreview` takes `accessibleName` and `accessibleDescription`
per instance (`layoutSummary` by default; the Windows page's effects preview
uses `effectsSummary`: blur, shadow, opacity and dimming).
`tests/test_settings_row_components.py` runs
`tests/harness/drivers/settings-row-components.qml` for these.
`SettingsSession` (singleton) keeps session-only UI state: `isHelpOpen(key)`,
`setHelpOpen(key, open)` and `requestReveal(key)`.

What rows rely on outside `components/`:

- `SettingsRegistry.search` also matches help texts and option labels and
  descriptions (English and translated, folded like the other fields; option
  texts score 30, between section/page titles and descriptions, and help
  texts 15, last). Each result carries `fields` (the field each query word
  matched: `label`, `keyword`, `context`, `option`, `description`, `help`)
  and `helpMatched` (a word matched only through the help);
  `SettingsShell` opens that row's help before revealing it.
- `SettingsStore.statusNote(key)` passes through the backend's optional
  `statusNote(entry)` hook: an English source string such as "Paused by Game
  Mode", or `""` when the backend has no hook or is unavailable, or the entry
  is read-only (`backendFor` gives no backend for entries that are not
  writable, whatever hook their backend has).
- `SettingsStore.defaultValue(key)` may be `undefined` (unknown): the row then
  hides the default tick and the reset button says "Reset".
- Tests: `tst_SettingsLogic` (chips, dependency wording, value formatting, the
  banner rule, search fields), `tst_SettingsStore` (`statusNote`, unknown
  defaults, unavailable backends) and `tests/test_settings_comprehension.py`,
  which runs `tests/harness/drivers/comprehension.qml` with and without
  `--hyprland-stub`: a word found only in a help text reveals its row with
  the help open, the "?" toggle works by keyboard, a "Requires …" chip is a
  keyboard link to its target (also on another page) said once to screen
  readers, rows show at most 2 chips, "Now: …" and the slider captions
  render (also on the color scheme and power mode rows), a row paused by Game Mode shows its italic, translated status note
  (the driver writes Game Mode's overrides file in the sandbox and delivers
  Hyprland's `configreloaded` through `SettingsStore.backends.hyprland`, a
  read-only map kept for drivers), the navigation count is hidden at 0 with
  its width reserved and described above 0, and no page title is elided at
  1100 and 1600 px (or at 760 px expanded), and the selected title fits its
  DemiBold width at the item's implicit width; without Hyprland, on the Windows,
  Input (list and text rows) and Animations pages, each section that shares
  the reason shows one banner and every Hyprland row shows "—" and no live
  control (`"rowControl"` hidden).

Shell components: `SettingsShell` (titlebar honoring `windows.showTitlebar`
and `windows.centerTitle`, navigation, page host, confirm bar, error toast),
`SettingsNavigation` (group headers and footer pages from `pages.json`; each
item shows `SettingsStore.modifiedCount(pageId)` after its title, hidden at 0
with its width reserved, as its accessible description "Changed
settings: <n>", and as a dot on the icon when collapsed; expanded, the list
is as wide as its longest page title needs in the selected weight beside the
reserved count (two digits in the count's own font, with 6 px between icon,
title and count; `SettingsMetrics.navExpandedWidth` 248 px at least,
`navMaxExpandedWidth` 320 px at most, longer titles elide), so titles are
never cut short and neither a count appearing nor a selection changes its
width; search
field with results showing the label and "Page › Section"; Ctrl+F focuses it,
Up/Down/Enter pick a result, Esc clears; collapses to icons below 900 px with
a menu button override that resets when the window crosses the threshold;
collapsed items show their title as a hover tooltip; the scrolled list fades
at its edges, and opening a page scrolls it so the page clears the fade, the
first page of a group together with its title), `SettingsPageHost`
(`setSource(pageId, source)`; pages are created once and kept, so switching
keeps the scroll position and never shows a blank frame; `ready`,
`currentItem`), `SettingsConfirmBar` ("Keep changes?", countdown,
Revert/Keep), `SettingsErrorToast` (failed writes, 5 s), plus
`SettingsButton` (`text`, `iconName`, `kind`), `SettingsIconButton`
(`iconName`, `tooltip`), `SettingsTextField`, `SettingsFocusRing` and the
`SettingsMetrics` singleton.

## Animation visuals

Standalone building blocks for the Animations page (plain properties and
signals; no registry, store or backend access). Curve descriptors are
`{ name, type: "bezier", points: [x1, y1, x2, y2] }` or
`{ name, type: "spring", mass, stiffness, damping }`, plus `label` (English
source string; `group: "user"` labels are shown as typed).

`CurveMath.js` (`.pragma library`, pure) ports hyprutils v0.14.3, the version
Hyprland 0.57 uses, in doubles (hyprutils uses floats). Compared with the real
libhyprutils, values match within 1e-6 for the built-in, dotfiles and app
curves; extreme user curves can differ by up to ~3e-4 near x = 1, and heavily
overdamped springs settle a few ms apart:

| Function | Meaning |
|---|---|
| `bezierY(points, x)` | `CBezierCurve::getYForPoint`: 255 baked points at t = 1/255..1, binary search, linear interpolation; 0 for x ≤ 0, 1 for x ≥ 1. |
| `advanceSpring(value, velocity, spring, dt)` | The closed-form damped-oscillator step of `Spring.cpp`. |
| `springProgress(spring, tMs)` | Position tMs after a start at rest; 1 from the tick Hyprland ends it. Frame-rate independent (closed form). |
| `springSettleMs(spring)` | When Hyprland ends a spring: the first 1 ms tick (Hyprland ticks animations from a 1 ms timer) with \|1 − value\| ≤ 0.001 and \|velocity\| ≤ 0.001. Soft spring 647 ms, bouncy spring 924 ms (the visible motion is mostly over by ~240/~360 ms). |
| `valueAt(curve, progress, durationMs)`, `durationMs(curve, speed)` | Animated value for a linear progress; a spring ignores `speed`. |
| `sample(curve, n)` | n evenly spaced `{x, y}` for thumbnails (a spring's x spans its settle time). |
| `speedToMs(speed)`, `msToSpeed(ms)` | speed × 100 (deciseconds); inverse rounded to 2 decimals. |
| `clampPoint(points)` | x in [0, 1], y in [-1, 2]; non-numbers become the lower bound. |

Golden values: `tests/curve_reference.py` (an independent Python port)
writes `tests/fixtures/curve-golden.json` with `--write`;
`tests/test_curve_math.py` fails when the fixture drifts from the reference
or from `config/hypr/hyprland/general.lua`, and runs
`tests/qml_settings/tst_CurveMath.qml` (JS vs fixture within 1e-6) with
`QML_XHR_ALLOW_FILE_READ=1` (Qt blocks local file reads without it).
`tests/test_settings_qml.py` sets the same variable for the whole
`qml_settings` suite and requires 0 skipped tests, so these fixture checks
and the `AnimationLogic` parity cases cannot be skipped silently.

Components:

- `SettingsCurveThumb { curve, selected, forceHovered, focusShown }`: the
  timing drawn with `QtQuick.Shapes` (curve renderer), y fitted inside
  [-1, 2] with faint guides at 0 and 1; `curve: null` shows a question mark.
- `SettingsCurvePicker { curves, value, accessibleName; activated(name) }`:
  radio group of thumbnails with translated labels. One Tab stop; arrows
  move, Home/End jump, Space/Enter choose; the picker never changes `value`
  itself. A value missing from `curves` gets an extra "Not recognized: X"
  item, selected, that keeps the value when chosen.
- `SettingsCurveEditor { points, originalPoints, baseCurves, durationMs;
  editedPoints; changed(points), accepted(points) }`: bezier only. `points`
  may be bound by the page: the editor never assigns it, edits its own copy
  `editedPoints` (read it, do not assign it) and loads `points` again
  whenever they change from outside (undo, reset, a backend revert; a new
  array with the same values counts as a change). Drag the two handles or
  type x/y (Up/Down step 0.01, Shift 0.1); x stays in [0, 1], y in [-1, 2],
  values round to 2 decimals and show the locale's decimal separator
  (typing accepts both comma and dot), out-of-range text shows a hint and is not
  applied. `changed` fires on every edit, `accepted` at the end of each one
  (release, Enter/focus loss, a step, "Start from…"). The original curve is
  drawn in grey; ▶ moves a ball along the curve for `durationMs`, past the
  end mark for overshooting curves but never out of its track (it stops at
  the edge for y near -1 or 2). Stacks below 560 px.
- `SettingsAnimationPreview` (contract in section 5 of the phase-A
  contracts, amended in wave 1): `family`, `kind`, `percent` (< 0 = not
  given), `direction`, `durationMs`, `curve`, `enabled`, `reduceMotion`,
  `play()`, `replay()`, `seek(progress)`, `playing`. When idle it shows the
  END state (the element at rest), also when `enabled` is false ("No
  animation" chip) or the family changes. `play()` is the explicit ▶: it
  always plays from the first frame, reduceMotion or not (a disabled one
  stays at the end). `replay()` is for automatic replays (a slider released,
  a value changed): it does nothing while `reduceMotion` is set, otherwise
  it is `play()`. The rounded frame is drawn above the mini screen, which is
  clipped to a rectangle inset inside the frame's rounded corners (a rounded
  shader mask would not draw in the software renderer), so moving content
  never covers the border. A mini screen per family: windows (popin N%, 100% = fade only;
  slide from a forced or the nearest edge; GNOME style), window move,
  workspaces (slide, slidevert, fade, slidefade/slidefadevert N%, forced
  direction), special workspace in/out over the dimmed workspace, shell
  panels entering from the screen edge, active border colour, zoom around the
  cursor. Geometry follows Hyprland's animation controllers. A linear
  `NumberAnimation` drives `progress` (marked `// motion-ok: Hyprland
  preview`, outside the shell motion scale) and `CurveMath.valueAt` maps it;
  springs last `springSettleMs` and carry an "Approximate" chip. It never
  loops.

`tests/harness/drivers/animation-visuals.qml` (run by
`tests/test_animation_visuals.py`) renders every component and state at 760
and 1100 px in the dark fixture theme and a light theme, fails on clipped
text or items past the edge, checks the picker keyboard, the editor's
clamping, validation (typed values whose every prefix is invalid), a bound
`points` that changes after an edit and the ball staying in its track for
[0.5, 2, 0.5, 2], the previews' frame geometry, idle end state,
`play()`/`replay()` rules and per-family geometry, and plays one preview to
its end:
`scripts/settings-harness/run.sh --strict --driver
tests/harness/drivers/animation-visuals.qml --sizes 1100x760 --out DIR`
leaves the screenshots in `DIR`.

## Animations page

`pages/AnimationsPage.qml` (registry `registry/animations.json`) renders, in
order: "What each part controls" (the intro), General ("Desktop
animations", the preset), Windows, Workspaces, Shell panels, Details, My
curves and "Motion inside the shell". Three row files of its own are chosen
by `widget` through `SettingsPage.rowSources`; the page adds the intro
delegate and the `applyMinimalPreset` action.

| Widget | Row | Key |
|---|---|---|
| `animation` | `SettingsAnimationRow` (+ `SettingsAnimationDetails`) | `animation.<card>` for the 10 cards, `path` = card id |
| `animationPreset` | `SettingsAnimationPresetRow` | `animation.preset` (also an alias on the Quick page, section "Look") |
| `curveLibrary` | `SettingsCurveLibraryRow` | `animation.curves` |

**Backend helpers.** The widgets reach the animation backend's read-only UI
helpers (`curveCatalog()`, `styleOptions(card)`, `presets()`,
`curveUsage(name)`, `summaryParts(card)`; "Backends -> animation") through
`SettingsStore.backends.animation`, inside bindings that read
`SettingsStore.revision` first so they refresh. Nothing writes through
`backends`: values are read with `SettingsStore.value(key)` and changed only
with `SettingsStore.write(key, value)` / `SettingsStore.reset(key)`, never
with the backend's `write`/`reset`/`flush`. The pure parts (summary text,
style changes, preset choices, the Undo plan, curve names and lists) are in
`components/AnimationsPageLogic.js` (`tests/qml_settings/tst_SettingsAnimationPageLogic.qml`).

**Cards** (`SettingsAnimationRow`). Folded, the label line has the modified
dot, and under it the reset button (while modified), the fold toggle, the summary
(`summaryParts` translated and joined: "Pop in 80% · 300 ms · Quick start,
gentle stop"; "No animation" when off; the shell panel cards leave the style
out), ▶ and the enable switch. Unfolded (the toggle, Space/Enter on it, a
click on the summary, ▶, or the row's highlight from a search hit or a
"Requires" jump) it adds `SettingsAnimationPreview` and the controls,
side by side from 640 px of row width and stacked below that:

- duration slider, 50 ms–2 s in 10 ms steps ("Short" … "Long"), written as
  Hyprland speed with `CurveMath.msToSpeed`; with a spring curve the slider
  is hidden and the card shows "≈ N ms (set by the spring)", N =
  `CurveMath.springSettleMs` rounded to 10 ms (also in the summary);
- `SettingsCurvePicker` over `curveCatalog()`; an unknown curve shows
  "Not recognized: X" and keeps the value;
- the style of the card's family from `styleOptions(card)`: kind ("Now: …"
  under it), a percent slider for `popin`/`slidefade*` and a side for `slide`;
  "Hyprland default" is offered only while the card has no style, and an
  unknown style shows "Not recognized: X" without losing it. Border, zoom and
  the two shell panel cards have no style control: `rules.lua` gives each
  shell panel its own entrance, so those cards set only duration and curve
  (their help lists which panels follow them and which do not).

Each control writes the whole card value on release or keyboard step. A
changed value (a control, Undo, a preset) calls the preview's `replay()`,
which does nothing under "Reduce motion in the shell"; ▶ calls `play()`,
which always plays. Tab order: fold toggle, ▶, switch, then (unfolded)
duration, curve picker, style, percent, side. Every control has a
`SettingsFocusRing`; the row's accessible description starts with the
summary. Cards and the preset have `enabledWhen` "Desktop animations" and
the `animationsLoaded` capability (the curve library only the capability):
without the loader in the deployed `hyprland.lua` every animation row is
disabled with "Hyprland does not load the animation settings yet: update the
dotfiles", so nothing is written to a file Hyprland ignores. Under
Game Mode they stay enabled, show their stored values and the status note
"Paused by Game Mode" (the backend's `statusNote`), and the page shows the
`info.animations.gameMode` banner.

**Preset** (`SettingsAnimationPresetRow`). Default · Agile · Smooth · Bouncy
· Minimal as a radio group (the option description shows as "Now: …"),
plus a disabled "Custom" while the cards match no preset. One write of
`animation.preset` is one backend change set (one generator call, one eval,
at most one reload); Default removes the animation lines and keeps the
curves. Choosing a preset while the state is Custom first captures every
card (`value` and whether the file holds it) and shows a 10 s bar with
[Undo]: Undo writes back the cards that were in the file and resets the
others, all in the same event-loop turn, so the backend sends one batch.
Another preset while the bar shows keeps that capture, names the new preset
in the bar and restarts its 10 s. Without the backend (Hyprland not running,
a foreign file) the row shows "—" and no "Now: …" note.
The description says that presets do not change the motion inside the
shell.

**Curves** (`SettingsCurveLibraryRow`). The user's curves with a thumbnail,
their label and "Used by: Section › Card"; [Add a curve] opens
`SettingsCurveEditor` ("Start from…" offers every bezier of the catalog) with
a "Name" field for the label; edit and delete per curve. Names are generated
(`ii_curve_N`, the backend rule `^ii_[a-z0-9_]{1,32}$`), never typed; the
label follows the backend's label rule. Delete is refused while
`curveUsage(name)` is not empty ("“X” cannot be deleted while a card uses
it: …"). The editor only makes beziers: a user spring (only from a
hand-edited or imported config) can only be renamed ("Springs are not edited
here…"), and keeps its mass, stiffness and damping. Every change writes the
whole list to `animation.curves`.

**Intro and shell motion.** The intro (`SettingsAnimationIntro`, custom
delegate of `info.animations.intro`) is a collapsible group of three boxes:
Desktop (Hyprland: the preset and the cards), Interface (the shell's own
motion: the last section) and Game Mode (turns desktop animations off while
on; values come back). "Motion inside the shell" lists "Reduce motion in the
shell" first and the speed after it (`enabledWhen` reduceMotion off: the
speed has no effect while it is on), and ends with
`action.animations.applyMinimal` ([Apply Minimal]): its text says the speed
controls above do not affect desktop animations; the button applies the
Minimal preset through the preset row (so a Custom state gets its Undo bar).
The action has the preset's `enabledWhen`, and the page gives it no handler
while the animation backend is unavailable, so it is never active when the
preset write can only fail. The Minimal description and the reduce-motion help
say that Minimal only shortens desktop motion (panels keep their slides);
turning off "Desktop animations" removes it.

**Tests.** `tests/test_animations_page.py` runs
`tests/harness/drivers/animations-page.qml` in the real window with
`--strict --hyprland-stub`, the `hyprctl` stub and the `python3` shim
(the `hyprctl -j animations` fixture is patched to what the driver's first
card write leaves, so the backend's `animationsLoaded` confirmation passes):
the 5 helpers reach the widgets through `SettingsStore.backends.animation`,
Tab order through a folded and an unfolded card, the unfolded controls show
the card's value, a search reveal unfolds a card, without the loader (no
`animationsLoaded`) every animation row and [Apply Minimal] are disabled with
the reason and a write runs nothing, an unavailable backend leaves the preset
without a "Now:" note and disables [Apply Minimal] as "Not available" (not
with the "not loaded yet" capability reason), adding a curve, renaming a
user spring keeps it a spring, a preset is
1 generator call / 1 eval / ≤1 reload and the Quick alias is the same preset
row with the same value, Default empties the animations and
keeps the curves, [Apply Minimal], a second preset renames the Undo bar and
Undo restores a custom state in one batch, deleting a used curve is refused,
reduceMotion stops automatic replays but not ▶ (every preview start is
recorded instead of sampling `playing` after a delay), a spring shows its settle time, Game Mode shows the note
and no "Requires", and an unfolded card at 760, 1100 and 1600 px overlaps no
other row (screenshots in `SHOT_DIR`, or `ANIMATIONS_PAGE_OUT` to keep them).

## App entry point

`settings.qml` is an `ApplicationWindow` (title "illogical-impulse
Settings", minimum 640×480) that sets `Config.readWriteDelay = 150` and
loads pages only once `Config.ready`. IPC: `qs -p settings.qml ipc call
settingsApp open <pageId>`, `… reveal <key>` and `… show`. Environment:
`II_SETTINGS_PAGE` opens a page and `II_SETTINGS_KEY` reveals a row at
startup. Closing the window hides it at once and quits after
`SettingsStore.finish`: a pending risky confirmation is reverted and queued
writes and restores finish first, since backends apply them through
asynchronous commands (quitting right away left an idle or display preview
applied and dropped writes still in their debounce). Any IPC call shows the
window again and cancels the quit. `SUPER+I` runs the launcher with the
session's `XDG_CURRENT_DESKTOP` (no `gnome` override), which the app's
helpers follow, e.g. `default-apps.py` for `<desktop>-mimeapps.list`.

Translations: `services/Translation.qml` tries the exact locale file, then
same-language files (`es` prefers `es_MX`, then `<lang>_<LANG>`, then any
`<lang>_*`), then English source strings; a file whose JSON is not an object
counts as `{}` (`services/TranslationFallback.js`).

## Motion inside the shell

Two `config` keys (Animations page, section "Motion inside the shell") change
the motion that Quickshell draws itself: menus, buttons, switches, sliders and
transitions inside panels. They do not touch Hyprland: how windows,
workspaces and shell panels (sidebars, bar, dock, notification popup) open
and close is Hyprland's `layersIn`/`layersOut` and the rest of that page.

| Key | Values | Effect |
|---|---|---|
| `appearance.animations.durationScale` | `0.5`, `0.75`, `1` (default), `1.5`, `2` (segmented: Very fast … Very slow) | Multiplies durations; 0.5 is twice as fast. Velocities are divided by the same factor. |
| `appearance.animations.reduceMotion` | `false` (default), `true` | Every preset transition (switches, sliders, menus, in-panel transitions) ends at once; the speed has no effect while it is on. The unmigrated durations below still move. |

`modules/common/functions/MotionScale.js` (pure, `tests/qml_settings/tst_MotionScale.qml`):
`factor(scale, reduce)` is 0 when `reduce` is `true`, otherwise `scale`
clamped to 0.25..3 (a missing or malformed value counts as 1);
`duration(ms, f)` is `max(1, round(ms × f))` and leaves 0, negative (`-1`)
and infinite durations untouched; `velocity(v, f)` is `v / f`, or `1e6` when
`f` is 0; `interval(ms, f)` follows the duration rule. The 1 ms floor is
deliberate: Qt finishes a 0 ms animation inside `start()` (the driver below
checks it), which would run `onFinished` handlers such as the notification
discard re-entrantly; 1 ms finishes on the next animation tick.

`Appearance.qml` exposes `animationFactor` (bound to both keys, so a change
applies live in the main shell and in the settings app), `scaled(ms)` and
`scaledVelocity(v)`. `scaled()` returns `real`, so `-1`, infinite and NaN
durations pass through untouched (an `int` return type turned Infinity into
a 0 ms animation); assigning it to an `int` duration still rounds. Every preset (`elementMove` 500, `elementMoveSmall` 350,
`elementMoveEnter` 400, `elementMoveExit` 200, `elementMoveFast` 200,
`elementResize` 300, `clickBounce` 400, `scroll` 200, `menuDecel` 350) and
its `velocity` go through them, and the factory Components bind to the
scaled values, so existing consumers follow. `animationCurves.*Duration` stay
raw constants; read the preset of the same base value instead
(`StyledSwitch`, `NavigationRailTabArray` use `elementMoveSmall`). Also
scaled: the timers that wait for an animation (`Overlay.qml`,
`BottomWidgetGroup.qml`, whose half duration keeps the 1 ms floor), the reveal
floors of `Authenticator.qml` and `AiQuotaPanel.qml`, and the
`SmoothedAnimation` velocities (`StyledSlider`, `CalendarHeaderButton`,
`TodoItemActionButton` through their preset; waffle `WSlider` and
`WProgressBar` through `Appearance.scaledVelocity`).

Not scaled on purpose, each marked `// motion-ok: <reason>` on the duration
line: endless loops and spinners (`MaterialLoadingIndicator`, the cookie
clock rotation, the song recognition button, the region selector pulse), the
clock second hand (real time), the brightness animation (it drives real
monitor writes), the reload popup timeout, and the raw
`animationCurves.*Duration` constants. Animation previews of Hyprland curves
must use Hyprland's own milliseconds and carry the marker too. The settings
search highlight pulse (`SettingsRow.qml`) is not scaled either.

About 56 hardcoded durations elsewhere (bar widgets, lock screen, clock
hands, ripples, text fades, the scrollbar, the settings app's own page
transitions) still ignore both keys; migrating them is deferred. The texts of
both keys say so: the reduceMotion help names what still moves.
`tests/test_motion_contract.py` scans `config/quickshell/ii/**/*.qml`
(waffle excluded) for duration bindings and assignments with a nonzero
literal that lacks `motion-ok` and fails when the count exceeds
`MAX_UNMIGRATED`. A literal is exempt only inside
`Appearance.scaled(...)`/`MotionScale.*(...)`, as the `1` of a
`Math.max(1, ...)` floor, or as a plain multiplier or divisor of a derived
duration (`rippleDuration * 2`, `preset.duration / 2`); a literal next to a
preset or derived duration (`Math.max(300, preset.duration)`,
`fooDuration > 0 ? 300 : 200`, `preset.duration ?? 200`) counts. Timer
`interval:` literals are counted separately (`MAX_UNMARKED_INTERVALS`, 18)
in files that use `Appearance.animation`, where a timer may wait for a
scaled animation; mark timeouts and polling with `// motion-ok: <reason>`.
Lower either constant when you migrate or mark a site; never raise it for
new code (wave 1 raised `MAX_UNMIGRATED` from 55 to 56 once, when the
scanner became stricter). The same test rejects readers of `animationCurves.*Duration`
outside `Appearance.qml` and scaled durations inside looping animations. It
also requires a 1 ms floor (`Math.max(1, ...)` or `Appearance.scaled()`) on
any arithmetic over a preset duration, `Appearance.scaled()` around the
Authenticator and AI quota `revealAnimation.duration` (so their floors scale),
and a preset velocity or `Appearance.scaledVelocity()` in every
`SmoothedAnimation`, waffle included. These are static checks: no test loads
those shell files. `tests/test_motion_scale.py` runs `tests/harness/drivers/motion-scale.qml`
with a config seeded at 0.5 (elementMove 250 ms, velocities doubled), then
`reduceMotion` (1 ms, and a preset factory animation emits `finished` after
`start()` returns) and back to 1 (500 ms), checks in each state that
`Appearance.scaled()` returns -1, Infinity and NaN unchanged, and renders the Animations page in
strict mode with the packaged config, which has neither key.

## Windows preview and system checks

**Window preview.** `components/SettingsWindowPreview.qml` is a `custom`
delegate of the Windows page, used twice: `info.windows.preview` at the top of
Spacing and borders (with the magnifier) and `info.windows.effectsPreview` at
the top of Blur (without it). It reads the page's values with
`SettingsStore.value()` and draws a 1280×800 desktop scaled to the row width:
the bar's 40 px strip, three dwindle tiles (gaps_out from the work area,
gaps_in on each side of a split, so neighbors are 2 × gaps_in apart; the
border outside the content, as `hyprctl -j clients` places windows), a
floating window with its shadow (range, render power; shadows only apply to
floating windows), active and inactive opacity, blur behind the bar and a
panel (the dotfiles' layer rules use xray, so they blur only the wallpaper)
and the dim of inactive windows, exaggerated ×3 and labelled so. The
magnifier is a 184×150 crop at 1:1 around the main window's top-right
corner, with the real gap, border, radius and rounding power (the
superellipse |x|^p + |y|^p = r^p; a dashed quarter circle shows p = 2), and
the sizes as text. Border colours come from `hyprctl -j getoption
general:col.active_border` / `col.inactive_border` (first colour of the
gradient), with the theme's colours until then. The page passes
`highlightKey`, the hovered row or else the row with focus; the preview
outlines the part that row changes (`WindowPreviewLogic.KEY_PARTS`) and
emphasises its magnifier label. Drawing is two `Canvas` items repainted only
when a value, the theme or the highlight changes: nothing animates. Without
Hyprland the preview shows example values (the dotfiles' own) and says so.
The geometry is pure (`components/WindowPreviewLogic.js`,
`tests/qml_settings/tst_SettingsWindowPreview.qml`).

**VRR capability.** `DisplayBackend` publishes `vrr` when an output of
`hyprctl -j monitors all` reports `hardwareDetails.vrrCapable` true or has
VRR active (`DisplayLogic.anyVrrCapable`; disabled outputs count, since
`misc:vrr` applies when they are turned on). `hyprland.misc.vrr` has
`enabledWhen: {"capability": "vrr"}`: the row stays visible and is disabled
with "No connected display supports variable refresh rate" when no output
can do it.

**Hyprland configuration errors.** `info.advanced.hyprlandErrors` (Advanced >
Diagnostics) runs `hyprctl -j configerrors` (argv, read-only) when the page
opens and on "Check again".
`pages/AdvancedLogic.js` `parseConfigErrors()` drops the empty strings of
Hyprland's `[""]` ("no errors"), keeps at most 100 lines and rejects anything
that is not a JSON list of strings ("Could not read the errors from
Hyprland."). The errors are shown as selectable, wrapped monospace text.
Without Hyprland the row says "Hyprland is not running" and has no button.

**Where settings are saved.** `info.advanced.diagnostics` lists the files the
backends write (shell config, `custom/shell-settings.lua`,
`custom/shell-idle.conf`, `monitors.lua`, `custom/shell-animations.lua`, the
shell folder) and the availability of every storage backend the registry
uses, with its unavailable reason. `tests/test_advanced_diagnostics.py` fails
when a registry backend is missing from that list. The config-errors fixtures
are copied into the harness `--out` directory, because `run.sh` mounts a
tmpfs over `/tmp`.

**Options added in this phase.** All are plain `hyprland` entries written to
`custom/shell-settings.lua`; none needed backend changes.

| Key | Page › section | Hyprland option | Model |
|---|---|---|---|
| `hyprland.input.scroll_factor` | Input › Mouse | `input:scroll_factor` | real 0.1–3 × |
| `hyprland.input.focus_on_close` | Input › Mouse | `input:focus_on_close` | enum next 0 · under the pointer 1 · last used 2 |
| `hyprland.cursor.hide_on_key_press` | Input › Mouse | `cursor:hide_on_key_press` | bool |
| `hyprland.input.touchpad.tap_and_drag` | Input › Touchpad | `input:touchpad:tap-and-drag` (Lua `tap_and_drag`) | bool, `touchpad` capability |
| `hyprland.input.touchpad.drag_lock` | Input › Touchpad | `input:touchpad:drag_lock` | enum 0–2, enabled while tap-and-drag is on |
| `hyprland.misc.middle_click_paste` | Windows › Behavior | `misc:middle_click_paste` | bool |
| `hyprland.binds.workspace_back_and_forth` | Windows › Workspaces | `binds:workspace_back_and_forth` | enum off 0 · all monitors 1 · per monitor 2 |
| `hyprland.misc.initial_workspace_tracking` | Windows › Workspaces | `misc:initial_workspace_tracking` | enum 0–2; the dotfiles' `false` reads as 0 |
| `hyprland.ecosystem.no_update_news` | Advanced › Hyprland notices | `ecosystem:no_update_news` | bool («Hide …») |
| `hyprland.ecosystem.no_donation_nag` | Advanced › Hyprland notices | `ecosystem:no_donation_nag` | bool («Hide …») |

The Windows page's Game Mode banner says what Game Mode overrides (blur,
shadows, animations, gaps, rounding, 1 px borders, tearing allowed); those
rows keep the stored value and say "Paused by Game Mode".

**Tests.** `tests/test_window_preview.py` runs
`tests/harness/drivers/window-preview.qml` (stub): 2 previews, writes of gaps,
border, rounding and rounding power reach the drawing (geometry checks, and
pixel checks of the 1:1 magnifier with Pillow), the focused row highlights
its part, real pointer moves (QtTest events) over previewed rows move the
highlight and leaving them falls back to the focused row
(`WindowsLogic.nextHoveredKey`, unit-tested in
`tst_SettingsWindowPreview.qml`), and Game Mode pauses the overridden rows
with their stored values. `tests/test_hyprland_e14.py` checks the registry entries, runs
`tests/harness/drivers/hyprland-e14.qml` (each option written, read back,
modified and reset through `HyprlandBackend`, one `hl.config` line each in
the generated file, which must pass `Hyprland --verify-config` in a private
HOME when Hyprland is installed), and runs
`tests/harness/drivers/config-errors.qml` with each
`tests/fixtures/hyprctl-configerrors-*.json` (none, two, malformed), the
stub's default and without the stub. The VRR capability is unit-tested in
`tst_DisplayPowerLogic.qml` with `tests/fixtures/hyprctl-monitors-all.json`
and variants; the parser in `tst_SettingsAdvancedLogic.qml`.

## Config schema version

`scripts/settingsctl.py validate|migrate [--dry-run] <config.json>` is a
development helper (`scripts/verify.sh` runs it on the packaged
`config/illogical-impulse/config.json`). It checks that the file is a JSON
object and adds the `_schemaVersion` marker; version 1 keeps the existing
shape. `migrate` writes atomically and keeps a
`<name>.pre-settingsctl-<timestamp>` copy first; `--dry-run` only reports.

## Harness contract

`settings.qml` keeps `pages` (array of page objects with `id`), a writable
`currentPage` index and `pageReady` (false while a page loads). The harness
(`scripts/settings-harness/run.sh`) renders pages offscreen in a sandbox and,
with `--strict`, fails on QML warnings, overlapping or overflowing `row:*`
items, popups open after load, any `config.json` write during the run, and
any file created, changed or removed under the sandbox's `hypr/custom/` or
`hypr/monitors.lua` ("unexpected write to hypr/custom/<name>"; run.sh records
sha256 manifests in `hypr.before.json`/`hypr.after.json`).
`--discard` deletes the output when the run passes. One page:
`scripts/settings-harness/run.sh --strict --pages bar --sizes 1100x760`.

Without Hyprland in the sandbox every Hyprland row renders unavailable
("Hyprland is not running"). `--hyprland-stub` puts
`tests/harness/stubs/hyprctl` first on `PATH` (a test's own `--env PATH=…`
still wins), sets `HYPRLAND_INSTANCE_SIGNATURE=settings-harness` and seeds the
sandbox config with copies of the repository's `config/hypr/hyprland.lua`,
`hyprland/general.lua`, `hyprland/colors.lua` and `hyprland/lib/` (never the
live `~/.config`). The stub logs each call's argv to `<out>/hyprctl.log`
(`HYPRCTL_LOG`) and answers from fixtures copied into the sandbox
(`HYPRCTL_FIXTURES`):

| Call | Answer |
|---|---|
| `-j descriptions` | Every option of `tests/fixtures/hyprland-options.json`, `current` = `default`. |
| `-j devices` | `tests/fixtures/hyprctl-devices.json` (keyboard, mouse, ELAN touchpad, lid switch). |
| `-j monitors [all]` | `tests/fixtures/hyprctl-monitors-all.json` (without `all`, enabled outputs only). |
| `-j animations` | `tests/fixtures/hyprctl-animations.json` (Hyprland 0.57 with these dotfiles). |
| `-j configerrors` | `[""]`, or the file named by `HYPRCTL_CONFIGERRORS`. |
| `[-j] getoption NAME` | The fixture default. |
| `eval EXPR` | `ok`, exit 0; when the regex `HYPRCTL_FAIL_MATCH` matches `EXPR`, `error: stub failure for <EXPR>` on stderr and exit 7. |
| other `-j` queries | `[]` or `{}` (binds, clients, workspaces, layers, …). |
| `reload`, `dispatch`, `keyword`, anything else | `ok`. |

With `--strict`, a `--hyprland-stub` run also fails when the stub never
answered `-j descriptions` or when a captured page shows Hyprland rows whose
backend is unavailable: `settings-shot.qml` reports, per page, the visible rows
whose backend is unavailable (`unavailable: {backend: count}`), and run.sh
passes `--hyprctl-log` to `summarize.py`. A run that silently fell back to the
"Hyprland is not running" state therefore cannot pass.

The stub has no event socket, so Quickshell.Hyprland's "Unable to find
hyprland socket" is listed in `tests/harness/known-env-warnings.txt`.

`tests/harness/settings-interact.qml` is the interaction driver:
`scripts/settings-harness/run.sh --strict --allow-config-writes
--hyprland-stub --driver tests/harness/settings-interact.qml`. It checks that accented and
unaccented searches return the same results and that activating one reveals
and highlights its row, that opening a page scrolls the page list so the page
clears the edge fade (the first page of a group with its group title), then,
for every visible and enabled `config` entry of
type `bool` or `enum`, calls `row.interact()`, checks that `config.json`
changed only that key, restores the original value (through the row's reset
when the original is the default) and checks the file again.
`--allow-config-writes` turns the strict `config.json` and `hypr/custom`
write checks into notes.
See `scripts/settings-harness/run.sh --help`.

## Tests

- `tests/test_settings_contract.py`: registry schema, unique keys, config
  paths exist in `ConfigOptions.qml` with compatible types, consumers exist
  and mention the key, retired keys hidden, translations present in
  `translations/es_MX.json`, service deny-list, no shell strings, no explicit
  `width:`/`height:` in settings components and pages (unless the line carries
  `// size-ok: <reason>`), pages use registered keys only, Hyprland entries
  match `tests/fixtures/hyprland-options.json`, every config option is
  registered, retired or managed elsewhere, capabilities in `enabledWhen`
  have a reason, and settings QML lives only in `backends/`, `components/`,
  `core/` and `pages/` (the scans cover all of it).
- QML unit tests under `tests/qml_settings/` (`tst_SettingsLogic`,
  `tst_SettingsStore` with `MockBackend`, `tst_TranslationFallback` and one
  `tst_<Backend>Logic` per backend's pure logic), run by
  `tests/test_settings_qml.py` with Qt 6 `qmltestrunner`
  (`/usr/lib/qt6/bin/qmltestrunner -input tests/qml_settings`;
  `/usr/bin/qmltestrunner` is the Qt 5 binary).
- Backend and helper tests: `test_hyprland_registry.py`,
  `test_hyprconfigurator.py`, `test_settings_display_power.py`,
  `test_display_rules.py`, `test_idlegen.py`, `test_monitorsgen.py`,
  `test_default_apps.py`, `test_hyprlock_time.py`, `test_open_settings.py`,
  `test_record_script.py`, `test_main_shell_ipc_contract.py`.
- Harness drivers under `tests/harness/drivers/`, each run by a test:
  `config-write-race.qml` (`test_config_write_race.py`),
  `spinbox-typed-commit.qml` (`test_spinbox_typed_commit.py`),
  `game-mode-state.qml` (`test_game_mode_state.py`),
  `hyprland-reload-fallback.qml` (`test_hyprland_reload_fallback.py`, with a
  stub `hyprctl` on `PATH`), `close-finishes-work.qml`
  (`test_settings_close.py`, stub `hyprctl`), `blank-choices.qml`
  (`test_settings_blank_choices.py`: every drop-down shows a value and every
  segmented choice has one selected).
- `test_settings_video_wallpaper.py` renders the pages with the wallpaper card
  in strict mode with a seeded video wallpaper (`run.sh --config`): the card
  previews `background.thumbnailPath`, never the video itself.
- `test_settings_harness.py`: the summarizer (including the `hypr/custom`
  check), `run.sh` arguments and the `hyprctl` stub.
- `scripts/verify.sh` runs everything, including the strict harness with
  `--hyprland-stub` at every size, one strict run without it at 1100x760 (the
  unavailable state) and the interaction driver with the stub.
