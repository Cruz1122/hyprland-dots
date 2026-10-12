# Settings migration baseline

This baseline belongs to the settings UI refactor. It does not claim that
the legacy pages have already been migrated.

## Boundaries

- Current settings entry point: `config/quickshell/ii/settings.qml`.
- Current pages: the ten files under `config/quickshell/ii/modules/settings/`.
- Current persistence boundary: `Config.options` and its existing write path.
- Current visual source of truth: `Appearance` and the common widgets.
- New components are isolated under `modules/settings/components/` until the
  page-by-page migration phase.

## Protected behavior

The new component layer must not change settings paths, value types, default
values, transforms, visibility/enabled dependencies, external commands, IPC,
URLs, clipboard actions, singleton services, persistence, or keyboard
shortcuts.

The initial loader keeps `active: Config.ready` and exposes its initial page
through a binding so it remains available when `Config.ready` starts false.

## Working-tree separation

The repository already contains unrelated local work. It must not be folded
into the settings UI migration:

- `config/quickshell/ii/scripts/colors/applycolor.sh`
- `config/quickshell/ii/scripts/colors/switchwall.sh`
- `scripts/verify.sh`
- `tests/test_terminal_colors.py`

Settings migration files are reviewed separately from those paths. No commit,
deploy, or live configuration change is part of this baseline phase.

## Phase checkpoints

| Phase | Expected evidence |
|---|---|
| 0 | This baseline and isolated diff boundaries. |
| 1 | `docs/settings-parity-matrix.md` and its contract test. |
| 2 | Fixed loader initialization and invalid `RowLayout` property. |
| 3 | `SettingsMetrics.qml` and the temporary component gallery. |
| 4 | Base `Settings*` components parse and pass contract checks without being used by legacy pages. |
