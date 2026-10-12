# Provenance and reconciliation

Modified distribution, 2026-10-12. This is not an official illogical-impulse
release. It retains the GPL-3.0 source base and credits of end-4/dots-hyprland.

## Source layers

- Prior local repository: `illogical-impulse-local`, original baseline commit
  `43d8ebc` through `dec99f2`, plus uncommitted settings/notes/authentication work.
- Live Hyprland and Quickshell `ii` config: captured 2026-10-12. At conflicting
  paths live files were selected, with both pre-reconciliation copies privately
  preserved. Repo-only files/tests/docs were retained. The public repository
  starts with a sanitized baseline; the previous seven commits stay in the
  original local repo and its private preservation backup, not in public history.
- Ancillary app configs/templates: captured from the same live desktop using
  the explicit allowlist in `scripts/dotsctl.py`.
- Dependency recipes/requirements: end-4/dots-hyprland commit
  `d192a25faa11cf1d56c839c344c9ef8dd6c2c69d`.
- Quickshell source pin: `7511545ee20664e3b8b8d3322c0ffe7567c56f7a`.
- Qt 6.12 backport: adapted from upstream
  `5d5d49873fe8cf1f99ddfd5006ceb2057c5c9b13`, credited to Cloud0310.
- Google Sans Flex installation source: end-4/google-sans-flex commit
  `251aa5abd30496368f634e54ce2a508fe5a2fdfa`, with its supplied license.
- Bundled static wallpaper: original SVG source and derived PNG, created for
  this project on 2026-10-12 under GPL-3.0. The owner's downloaded video is not
  redistributed; its generated restore script remains in the private backup.

## Public-preset differences from the owner's machine

The top bar/sidebar source is retained. Only portability-related preset data
is changed: home paths become install-time placeholders, downloaded video and
thumbnail references become an original static wallpaper, and NVIDIA-specific
environment settings are not imposed on other machines. The active desktop
configuration was not deployed over or replaced during this reconciliation.

## Dependency boundaries

Upstream package recipes retain their source URLs and license declarations;
software/fonts fetched during installation are not relicensed by this project.
Inherited Quickshell assets and Kvantum themes retain their original notices
and authorship. No claim is made that these third-party assets were authored
by Cruz1122. Review source-specific licensing before independently repackaging
assets or binaries.

## Evidence and remaining validation

The pinned original Quickshell failed with Qt 6.12 due to incomplete metatypes.
The adapted upstream backport compiled successfully on CachyOS with Qt 6.12.0
and GCC 16.2.1, passed the compatibility check and loaded a minimal offscreen
QML config. Package installation requires the owner's sudo authorization.
These checks do not replace validation of a fresh full shell/session.

Fresh Arch/CachyOS VM installation and multi-GPU visual testing remain pending.
The repository includes tests for isolated installation/capture, preserving
customizations, repeated runs, verified backups and symlink boundaries.
