# Settings Foundation

This document defines the first safe implementation layer for the expanded
illogical-impulse settings UI.

## Goals

- All setting mutations must go through a typed settings boundary.
- Config files must be read, validated, migrated, and written atomically.
- Runtime state and secrets must not be stored in `config.json`.
- Live deployment remains explicit and backed up.

## Current schema

- Schema version key: `_schemaVersion`.
- Current version: `1`.
- Version `1` preserves the existing config shape and only adds the schema
  marker when it is missing.

## Mutation rules

1. Load JSON with duplicate-free object semantics where possible.
2. Validate top-level type is an object.
3. Migrate in deterministic version steps.
4. Write to a temporary file in the same directory.
5. Flush and replace the target atomically.
6. Keep a timestamped `.pre-settingsctl-<timestamp>` copy before mutation.

## Backend categories

- `config`: pure JSON-backed UI preferences.
- `hyprland`: generated Lua overrides and runtime `hyprctl` reconciliation.
- `audio`: PipeWire/WirePlumber state and persistent device preferences.
- `power`: UPower, power-profiles-daemon, logind, and hypridle generation.
- `capture`: screenshots, recording, OCR, and privacy orchestration.
- `desktop`: wallpaper, animated wallpaper, theming, and panel families.
- `connectivity`: NetworkManager and BlueZ.

## Immediate-apply contract

The UI can apply changes immediately, but each backend operation must expose:

- requested value;
- previous value;
- effective value after reconciliation;
- success/failure status;
- rollback action when the backend rejects the change.
