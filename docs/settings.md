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
| `desktop` | `windows`, `input`, `displays` |
| `system` | `sound`, `power`, `notifications`, `apps`, `region` |
| `tools` | `capture`, `search`, `services` |
| footer | `advanced`, `about` |

Each page id has `registry/<id>.json` and `pages/<Id>Page.qml`.

Sections per page, in order (the registry files are authoritative; the last
column counts entries, including actions and read-only rows):

| Page | Title | Sections | Entries |
|---|---|---|---|
| `quick` | Quick settings | Look, Bar, System | 0 + 10 aliases |
| `appearance` | Appearance | Color, Transparency, Typography, Colors from the wallpaper, Shell windows | 26 |
| `background` | Wallpaper and widgets | Wallpaper, Parallax, Clock, Cookie clock, Digital clock, Quote, Weather widget | 39 |
| `bar` | Bar | Layout, Auto-hide, Workspaces, Buttons, Indicators and tooltips, Resources, Weather, System tray | 34 |
| `panels` | Panels and overlays | Right sidebar, Open from screen corners, Dock, Overview, Overlay, On-screen display, On-screen keyboard, Shortcut cheat sheet, Media | 48 |
| `windows` | Windows and effects | Game Mode, Spacing and borders, Blur, Shadows, Dimming, Opacity, Animations, Behavior, Gestures, Window rules | 35 |
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
| `key` | Globally unique id. For `config` it is the config path. Other backends use a prefix: `hyprland.<lua path>`, `display.<field>`, `mime.<role>`, `audio.<x>`, `power.<x>`, `ipc.<x>`, `action.<page>.<name>`, `info.<page>.<name>`. |
| `section` | Section id of the same page. |
| `label`, `description` | English source strings, translated with `Translation.tr`. Description is one sentence. |
| `note` | Optional English hint shown under the description (for example "Applies to new windows"). |
| `keywords` | Optional extra search terms (any language). |
| `icon` | Optional Material Symbols name. |
| `backend` | `config`, `hyprland`, `idle`, `display`, `mime`, `audio`, `power`, `ipc`, `action`, `readonly`. |
| `path` | Backend address. Defaults to `key` for `config`. Hyprland: Lua path such as `input.touchpad.tap_to_click`. |
| `option` | Hyprland only: `hyprctl getoption` name, such as `input:touchpad:tap-to-click`. Lua keys use `_`, option names may use `-`. |
| `type` | `bool`, `int`, `real`, `enum`, `string`, `path`, `font`, `color`, `list`, `time`, `url`, `action`, `info`, `custom`. |
| `widget` | Optional rendering hint: `switch`, `slider`, `spin`, `segmented`, `select`, `text`, `textarea`, `path`, `font`, `color`, `list`, `time`, `device`, `action`, `info`, `custom`. |
| `min`, `max`, `step`, `unit`, `uiScale`, `decimals` | Numeric range and display. `uiScale` multiplies the stored value for display (0.5 shown as 50 with `unit: "%"`); `min`/`max`/`step` stay in stored units. Spin boxes round the displayed value and write it divided back and rounded (seconds shown as minutes with `uiScale: 1/60`). |
| `options` | Enum values: `[{ "value": <json>, "label": "English", "icon": "optional" }]`. |
| `validate` | `{ "regex": "...", "maxLength": n, "nonEmpty": true, "unique": "<group>" }`. |
| `enabledWhen`, `visibleWhen` | Conditions, below. |
| `risky` | Needs the 15 s keep-or-revert confirmation. |
| `action` | For `type: "action"`: handler name provided by the page. |
| `consumers` | Files (relative to `config/quickshell/ii`, or repo-relative when starting with `config/`/`scripts/`) that read the setting. Required for `config`; each must contain the leaf key name. |
| `external` | Optional script that consumes the value. |
| `keys` | For composite/custom widgets: every config path they write. |
| `actionLabel`, `actionIcon`, `actionKind` | `action` rows: English button text (default "Open"), icon and `SettingsButton` kind (`tonal`, `filled`, `danger`, `text`). |
| `placeholder` | Text rows: English placeholder. |
| `pick` | Path rows: `"folder"` (default) or `"file"` for the picker button. |

A page object may also carry `iconRotation` (degrees, for example `bar`).
Unknown entry fields are rejected by the contract test.

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
`multiMonitor`; `satty` and `checkupdates` come from the `system` backend,
`ipc:<target>` from the `ipc` backend). An entry whose backend is not
available renders disabled with the backend's `unavailableReason`. An entry
disabled by a missing capability shows `capabilityReason(name)` from
`core/SettingsLogic.js` ("Requires satty, which is not installed", "No
touchpad detected", …); a capability used in `enabledWhen` needs its own text
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
deferWrites`, `previewReset(entry)`. `write`, `reset`, `preview`, `persist`
and `restore` return `false` when they fail synchronously. The
`SettingsStore` singleton instantiates one of each backend.

| Backend | Persistence and apply |
|---|---|
| `config` | `config.json` through `Config`; the main shell reacts through its file watch. |
| `hyprland` | `~/.config/hypr/custom/shell-settings.lua`, required by `config/hypr/hyprland.lua` after `custom/*` and `monitors.lua` and before `hyprland.shellOverrides.main` (Game Mode keeps winning while active). Effective values come from one `hyprctl -j descriptions` at start and after every `configreloaded`; an entry is modified when the file overrides it (`hyprconfigurator.py --list --json`). Normal writes coalesce for 400 ms into one `hyprconfigurator.py --set-typed/--unset` call (types from the registry, not from Hyprland's defaults); writing the file triggers Hyprland's autoreload. Risky values preview with `hyprctl eval 'hl.config({...})'`, are re-applied after any reload while the confirmation lasts, and are written only on confirm. A risky reset removes the override at once (`previewReset`) and restore puts it back. While any confirmation is pending (`deferWrites`), normal file writes wait, because the reload they trigger would drop live previews. Never `hyprctl reload` or `keyword`. Capabilities: `touchpad` (`hyprctl -j devices`), `gameMode` (Game Mode's line in `shellOverrides/main.lua`). |
| `idle` | `idle.*` in `config.json`, rendered by `scripts/settings/idlegen.py --restart` into `~/.config/hypr/custom/shell-idle.conf` (sourced by `config/hypr/hypridle.conf`); hypridle reads its config only at start, so every apply restarts it. Risky: the preview renders and restarts, `config.json` is written on confirm, restore renders the previous values. Nothing is written on load: a file that differs from `config.json` publishes `idleOutOfSync` ("Apply" action) and a file without the marker `idleUnmanaged` ("Replace"). |
| `display` | State from `hyprctl -j monitors all` (disabled outputs included), as a `monitorsgen.py` spec. Preview: `monitorsgen.py --lua-expr --spec-json …`, then `hyprctl eval` with that expression; `~/.config/hypr/monitors.lua` is written only on confirm, with a marker header. A file without the marker is never overwritten silently: `monitorsFileUnmanaged` offers "Replace (keeps a backup)", which uses `--force`. The last enabled output cannot be turned off. Risky. |
| `mime` | `scripts/settings/default-apps.py list --json` and `set <role> <desktop-id>` (argv). It implements the freedesktop MIME association spec directly and edits `mimeapps.list` in place, because the installed `xdg-mime` ignores `hyprland-mimeapps.list` and rejects apps whose `Exec` is quoted. A candidate must open the role's primary type; setting it claims only the types it declares. The current default may be an app that is not a candidate (hidden or `NoDisplay`), and the page still shows it. |
| `audio` | `Quickshell.Services.Pipewire` preferred default sink and source; duplicate HDMI nodes are merged. Capability `pipewire`. |
| `power` | `Quickshell.Services.UPower` power profiles (the performance profile only when offered) and the `battery` capability (`UPower.displayDevice.isLaptopBattery`). |
| `system` | No entries. Probes optional tools once at start with `which <tool>` (argv) and publishes the found ones as capabilities (`satty`, `checkupdates`), independent of the main shell. Always available. |
| `ipc` | `qs -p <shell dir> ipc call …` to the main shell, which is the same instance as `qs -c ii` (Do Not Disturb through `notifications`, AI quota connect through `aiQuotaPanel.connectProvider`, region recording through `region`). Available while `ipc show` answers; polled every 10 s while the app is open. The app never starts `ai-quotas.py serve` itself. |

Helper scripts (`scripts/settings/`, run as `python3 <script>` with argv;
exit 0 ok, 1 I/O error, 2 invalid input unless noted):

| Script | Interface |
|---|---|
| `idlegen.py` | `[--lock S] [--dpms S] [--suspend S] [--output PATH] [--force] [--print] [--restart]`. Seconds, 0 = never, otherwise 30–86400 with lock ≤ dpms ≤ suspend. Exit 3: target without the marker (needs `--force`); exit 4: hypridle could not be restarted (`systemctl --user restart` when the unit is active, otherwise `pkill -x hypridle` and a new detached instance). |
| `monitorsgen.py` | `[--output PATH] [--force] [--print \| --lua-expr [--name OUTPUT]] [--spec-json TEXT]`; the spec (`{"monitors": [...]}`) comes from `--spec-json` or stdin. `--force` backs up an unmanaged file to `<name>.bak-YYYYmmdd-HHMMSS`. Exit 3: unmanaged target. |
| `default-apps.py` | `list [--json]`, `set ROLE DESKTOP_ID`; roles `browser`, `fileManager`, `mail`, `image`, `video`, `audio`, `text`, `pdf`. |
| `hyprlock-time.py` | `24h\|12h [--file PATH]`: switches `$TIME`/`$TIME12` in `hyprlock.conf` atomically; a missing file is not an error. |
| `open-settings.sh` | `[pageId [settingKey]]`: single instance; forwards to `settingsApp.open`/`reveal` over IPC or starts the app with `II_SETTINGS_PAGE`/`II_SETTINGS_KEY`. |

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
| `rowEnabled`, `disabledReason` | `isEnabled` plus `extraEnabled`; the reason line shows the backend reason, `Depends on “<label>”` or the capability's reason. |
| `highlighted`, `pulse()` | Search reveal highlight. |
| `busy`, `errorText` | `errorText` follows `SettingsStore.failed` for this key and clears on `committed`. |
| `hovered` | `HoverHandler`. |
| `stacked`, `controlFillsWidth`, `controlPreferredWidth` | Layout: the control goes below the text when `stacked`, the row is narrower than 520 px, or the control needs more than 55% of the width. Drop-downs share `SettingsMetrics.selectWidth` so a section's controls line up; long labels elide. |
| `focusVisible` | Variants bind it to their control's `visualFocus`; draws the focus ring. |
| `commit(value)` | `SettingsStore.write`; emits `rejected()` on failure so the variant resyncs its control. |
| `resetToDefault()` | Reset button (shown only when modified and enabled). |
| `activateHandler`, `interact()` | Click on the row outside the control; `interact()` performs the primary interaction (switch flips, select/segmented move to the next option) and returns `false` when the variant has none. The harness driver uses it. |
| default children | The control, placed in a `RowLayout` on the right. |

Variants (all take `settingKey`): `SettingsSwitchRow`, `SettingsSliderRow`
(`uiScale`, `unit`, `decimals`; writes on release or keyboard step),
`SettingsSpinRow` (integers; typed text commits on Enter/focus loss),
`SettingsSelectRow`, `SettingsSegmentedRow`, `SettingsTextRow`
(Enter/focus loss commits, Esc restores), `SettingsTextAreaRow` (commits on
focus loss), `SettingsPathRow` (folder/file picker), `SettingsFontRow`
(installed families), `SettingsColorRow` (hex with swatch; empty =
automatic), `SettingsListRow` (chips plus add field), `SettingsTimeRow`
(zero-padded hour and minute spin boxes), `SettingsDeviceRow` (select over
`SettingsStore.choices`), `SettingsActionRow`, `SettingsInfoRow`,
`SettingsCustomRow`. Rows show the stored value through `Binding {
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

A page file is just `SettingsPage { pageId: "<id>"; ... }`; pages with no
entries show an empty state. Sections render as `SettingsSection`
(`sectionId`, `title`, `icon`, `description`, rows as default children,
`objectName: "section:" + id`).

Shell components: `SettingsShell` (titlebar honoring `windows.showTitlebar`
and `windows.centerTitle`, navigation, page host, confirm bar, error toast),
`SettingsNavigation` (group headers and footer pages from `pages.json`; search
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

## App entry point

`settings.qml` is an `ApplicationWindow` (title "illogical-impulse
Settings", minimum 640×480) that sets `Config.readWriteDelay = 150` and
loads pages only once `Config.ready`. IPC: `qs -p settings.qml ipc call
settingsApp open <pageId>` and `… reveal <key>`. Environment: `II_SETTINGS_PAGE`
opens a page and `II_SETTINGS_KEY` reveals a row at startup. Closing the
window with a pending risky confirmation reverts it before quitting.

Translations: `services/Translation.qml` tries the exact locale file, then
same-language files (`es` prefers `es_MX`, then `<lang>_<LANG>`, then any
`<lang>_*`), then English source strings; a file whose JSON is not an object
counts as `{}` (`services/TranslationFallback.js`).

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
items, popups open after load, and any `config.json` write during the run.
`--discard` deletes the output when the run passes. One page:
`scripts/settings-harness/run.sh --strict --pages bar --sizes 1100x760`.

`tests/harness/settings-interact.qml` is the interaction driver:
`scripts/settings-harness/run.sh --strict --allow-config-writes --driver
tests/harness/settings-interact.qml`. It checks that accented and
unaccented searches return the same results and that activating one reveals
and highlights its row, that opening a page scrolls the page list so the page
clears the edge fade (the first page of a group with its group title), then,
for every visible and enabled `config` entry of
type `bool` or `enum`, calls `row.interact()`, checks that `config.json`
changed only that key, restores the original value (through the row's reset
when the original is the default) and checks the file again.
`--allow-config-writes` turns the strict config-write check into a note.
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
  `game-mode-state.qml` (`test_game_mode_state.py`).
- `scripts/verify.sh` runs everything, including the strict harness and the
  interaction driver.
