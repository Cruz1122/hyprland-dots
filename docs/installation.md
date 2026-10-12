# Installation and maintenance

## Scope and safety

Target: x86-64 Arch Linux and CachyOS with an installed OS, networking and a
normal desktop user who can use sudo. This is not an OS or GPU-driver installer.
Hyprland 0.56+ (Lua configuration) is required. Other distributions, older
Hyprland and non-default runtime XDG layouts are not supported yet.

The installer is a first implementation, not yet validated end-to-end on a
fresh Arch/CachyOS VM. Do not interpret unit tests as hardware validation.

`./install.sh` asks for confirmation. Package managers retain their own prompts.
It uses a full system upgrade, reviewed AUR dependencies and bundled local
PKGBUILDs derived from illogical-impulse. Internet, build space and time are
required. Review `packaging/arch/` before trusting its executable recipes.
No upstream dotfile installer is run: it would overwrite customizations and its
dependency cleanup removes packages with `-Rdd`.

## Commands

```bash
./install.sh --dry-run
./install.sh
```

Already have dependencies? Use `./install.sh --skip-deps`. This skips packages
and Python environment creation; it is not a way to repair an incompatible Qt
installation. For unattended config acceptance, add `--yes` (sudo/AUR may still
ask). Existing `hypr/custom/`, monitor/workspace configuration, `hyprland.conf`
and `illogical-impulse/config.json` are preserved. To intentionally replace
these, review a dry run and explicitly add `--replace-user`.

Files outside the deployed set are never deleted. Sources are copied, not
symlinked to the clone. Existing destination symlinks that could be followed
are rejected; internal source icon symlinks are retained. Installation does
not restart Hyprland/Quickshell, log out, enable privileged services or restore
old snapshots. Configuration copying can trigger an application's own file
watcher; install from another session/TTY if you do not want a hot reload.

On failure, stop and inspect the printed private backup and error. There is no
automatic rollback, and changing configuration does not undo package upgrades.

## Optional device setup

PipeWire, WirePlumber, portals, Bluetooth and keyring integration depend on the
base OS/session. Enable services appropriate to your system, not blindly:

```bash
systemctl --user status pipewire wireplumber
systemctl status bluetooth
```

`ydotool`/virtual keyboard and DDC monitor brightness need suitable services,
device permissions and, for DDC, the `i2c-dev` kernel module. The installer
does not add users to `input` or change system udev rules automatically.
NVIDIA drivers/settings are machine-specific; no NVIDIA environment override
is imposed on fresh installations. Use `hypr/custom/env.lua` for local tuning.
No display manager, login shell, Wi-Fi credentials, AI keys or account is
configured for you. Optional AI services are not installed.

## Source of truth

Edit the clone and review before deployment. If you edit live configuration,
capture it before pulling/deploying anything:

```bash
python3 scripts/dotsctl.py capture --dry-run
python3 scripts/dotsctl.py capture --yes
git diff
```

Capture uses a desktop-only allowlist, backs up the repository's config first,
prefers live files at conflicting paths and never deletes repository-only
files. All other repository files and history remain intact. It replaces the
current home/config prefix with install-time `@HOME@` / `@CONFIG@` placeholders.
**Capture is not an automatic secret scrubber**: review settings, hardware,
wallpaper dependencies, licenses and the diff before committing. Runtime notes,
authenticator/keyring data, AI chats, venvs, thumbnails and installer markers
are not source files. Never copy all of `~/.config` into Git.

The public preset uses an original bundled static wallpaper, not the owner's
unlicensed download. The private preservation backup retains original paths
and the generated video restoration script. Select your own wallpaper after
installation; current user's existing settings are preserved by default.

## Current-state backups

Private backups are under `$XDG_STATE_HOME/hyprland-dots/backups` (default
`~/.local/state/hyprland-dots/backups`), have unique names, restrictive directory
permissions and a manifest of file hashes/symlink targets. Installation backs
up only configuration roots managed by this repository, not browser profiles.

```bash
python3 scripts/dotsctl.py verify-backup --backup /path/printed/by/installer
```

There is deliberately no automatic restoration of these backups. Restore
individual reviewed files only if you explicitly decide to; do not confuse
them with previous system snapshots. The old `restore-backup.sh` helper handles
the previous illogical-impulse backup layout and is manual-only legacy tooling.

## Quickshell after a Qt upgrade

Check before ending the current session:

```bash
quickshell --private-check-compat
bash scripts/rebuild-quickshell.sh
```

The rebuild script builds but does **not** install or restart anything. It
prints an explicit `sudo pacman -U` command. The recipe pins commit
`7511545ee20664e3b8b8d3322c0ffe7567c56f7a` and backports the Qt 6.12 fix from
upstream commit `5d5d49873fe8cf1f99ddfd5006ceb2057c5c9b13` (MOC includes and
out-of-line bindable accessors). It does not downgrade Qt or move to HEAD.

After installing the package, run the compatibility check again. A successful
minimal QML smoke test is not proof that every widget works: test a controlled
new desktop session when ready. Do not run a second full shell on your active
session just to check syntax: it starts services and changes state.

## Verification

```bash
bash scripts/verify.sh
```

Tests use temporary homes/configs and never deploy to your real desktop.
Migration/encryption domain tests need `tests/requirements.txt`; use a test venv
on systems where those Python dependencies are not already installed.
Release evidence still requires fresh Arch/CachyOS VM installations, repeated
install, failed-install handling and visual checks of bar/sidebar/settings,
audio, lock, screenshots, QR, keyboard layout and multiple GPU/monitor setups.

A killed capture/install can leave `operation.lock` under the backup state root.
Confirm that no installer/capture is running before manually removing the empty
lock directory. Do not remove a live operation's lock to bypass concurrency.

References: [Arch system maintenance](https://wiki.archlinux.org/title/System_maintenance),
[Arch AUR](https://wiki.archlinux.org/title/Arch_User_Repository),
[Hyprland](https://wiki.hypr.land/),
[Quickshell Qt 6.12 fix](https://git.outfoxxed.me/quickshell/quickshell/commit/5d5d49873fe8cf1f99ddfd5006ceb2057c5c9b13).
