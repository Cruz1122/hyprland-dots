#!/usr/bin/env bash
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cache="${XDG_CACHE_HOME:-$HOME/.cache}/hyprland-dots/build"
mkdir -p "$cache"
# Full upgrades only. pacman and AUR retain their own review/confirmation prompts.
sudo pacman -Syu --needed base-devel git python uv ripgrep fontconfig libsecret zbar python-protobuf python-cryptography
if command -v paru >/dev/null; then
  helper=paru
elif command -v yay >/dev/null; then
  helper=yay
else
  printf 'No AUR helper found. Building yay from https://aur.archlinux.org/yay.git\n'
  if [[ ! -d "$cache/yay/.git" ]]; then
    git clone https://aur.archlinux.org/yay.git "$cache/yay"
  fi
  printf 'Review %s/PKGBUILD before approving the build.\n' "$cache/yay"
  read -r -p 'Build and install yay? [y/N] ' answer
  [[ "$answer" == y || "$answer" == Y ]] || exit 1
  (cd "$cache/yay" && makepkg --syncdeps --install)
  helper=yay
fi
for recipe in "$root"/packaging/arch/illogical-impulse-*; do
  name="${recipe##*/}"
  if [[ "$name" == illogical-impulse-quickshell-git ]]; then
    if command -v quickshell >/dev/null && quickshell --private-check-compat; then
      continue
    fi
  elif pacman -Q "$name" >/dev/null 2>&1; then
    continue
  fi
  # Recipes shipped in this repository are executable, reviewed source.
  dependencies=()
  mapfile -t dependencies < <(bash -c 'source "$1"; printf "%s\n" "${depends[@]}" "${makedepends[@]}"' _ "$recipe/PKGBUILD")
  "$helper" -S --needed "${dependencies[@]}"
  build="$cache/$name"
  mkdir -p "$build"
  cp -a "$recipe/." "$build/"
  (cd "$build" && makepkg --cleanbuild --force --syncdeps --install)
done
quickshell --private-check-compat
hypr_version="$(pacman -Q hyprland | cut -d ' ' -f 2)"
if (( $(vercmp "$hypr_version" 0.56) < 0 )); then
  printf 'Hyprland 0.56+ is required for Lua configuration.\n' >&2
  exit 1
fi
if ! fc-list : family | rg -qi 'Google Sans Flex'; then
  font_source="$cache/google-sans-flex"
  if [[ ! -d "$font_source/.git" ]]; then
    git clone --no-checkout https://github.com/end-4/google-sans-flex.git "$font_source"
  fi
  git -C "$font_source" checkout --detach 251aa5abd30496368f634e54ce2a508fe5a2fdfa
  fonts="${XDG_DATA_HOME:-$HOME/.local/share}/fonts/hyprland-dots-google-sans-flex"
  mkdir -p "$fonts"
  cp -an "$font_source"/*.ttf "$font_source/LICENSE" "$fonts/"
  fc-cache -f "$fonts"
fi
venv="${XDG_STATE_HOME:-$HOME/.local/state}/quickshell/.venv"
if [[ ! -x "$venv/bin/python" ]]; then
  uv venv --python 3.12 "$venv"
fi
uv pip install --python "$venv/bin/python" -r "$root/packaging/requirements.txt"
printf 'Core dependencies ready. Optional device/service setup: see docs/installation.md.\n'
