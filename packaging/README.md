# Dependency provenance

The Arch package recipes and Python requirements were imported from
[end-4/dots-hyprland](https://github.com/end-4/dots-hyprland), revision
`d192a25f` (full revision recorded in `docs/provenance.md`). Original authors'
notices and source/license declarations are retained.

We deliberately do not use upstream's dependency-removal or config installer
scripts. Our dependency runner preserves existing compatible packages and
never uses `pacman -Rdd`, partial upgrades or an unreviewed `curl | sh`.
The recipes may still pull AUR dependencies; these are third-party executable
build instructions and require normal package-manager review.

Modified 2026-10-12: Quickshell pkgrel 9 adds a narrow backport of upstream
`5d5d498` to the existing source pin for Qt 6.12. The Python backport asserts
expected source fragments and aborts rather than silently patching a new tree.
Build outputs and virtual environments are intentionally not versioned.
