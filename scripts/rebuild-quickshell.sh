#!/usr/bin/env bash
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
build="${XDG_CACHE_HOME:-$HOME/.cache}/hyprland-dots/build/illogical-impulse-quickshell-git"
(( EUID != 0 )) || { printf 'Build as a normal user, not root.\n' >&2; exit 1; }
command -v makepkg >/dev/null
mkdir -p "$build"
cp -a "$root/packaging/arch/illogical-impulse-quickshell-git/." "$build/"
(cd "$build" && makepkg --cleanbuild --force --syncdeps)
printf '\nBuild complete; no package installed and no session restarted.\n'
printf 'Install explicitly: sudo pacman -U'
for package in "$build"/illogical-impulse-quickshell-git-*.pkg.tar.zst; do
  printf ' %q' "$package"
done
printf '\nThen run: quickshell --private-check-compat\n'
