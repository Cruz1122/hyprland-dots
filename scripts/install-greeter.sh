#!/usr/bin/env bash
# Installs the Quickshell login screen for greetd into /etc/greetd and
# /etc/pam.d/greetd. It does not enable greetd or disable the current display
# manager; docs/greeter.md has the test and switch steps.
#
# usage: scripts/install-greeter.sh [--dry-run] [--name NAME] [--avatar FILE] [--wallpaper FILE]
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
src="$root/system/greeter"
generated="${XDG_STATE_HOME:-$HOME/.local/state}/quickshell/user/generated"
dry_run=false
wallpaper=""
name=""
avatar=""

while (($#)); do
  case "$1" in
    --dry-run) dry_run=true ;;
    --name)
      name="${2:?--name needs a value}"
      shift
      ;;
    --avatar)
      avatar="${2:?--avatar needs a file}"
      [[ -f "$avatar" ]] || { printf 'No such avatar: %s\n' "$avatar" >&2; exit 1; }
      shift
      ;;
    --wallpaper)
      wallpaper="${2:?--wallpaper needs a file}"
      [[ -f "$wallpaper" ]] || { printf 'No such wallpaper: %s\n' "$wallpaper" >&2; exit 1; }
      shift
      ;;
    *) printf 'Unknown argument: %s\n' "$1" >&2; exit 2 ;;
  esac
  shift
done

missing=""
command -v greetd >/dev/null || missing='greetd is not installed. Install it first: sudo pacman -S greetd'
[[ -n "$missing" ]] || getent passwd greeter >/dev/null || missing='The greeter user does not exist; reinstall the greetd package.'
if [[ -n "$missing" ]]; then
  printf '%s\n' "$missing" >&2
  $dry_run || exit 1
fi

# The greeter runs as another user and cannot read this home: stage a theme
# snapshot (colors, title font, user name, avatar) next to the QML.
stage="$(mktemp -d)"
trap 'rm -rf -- "$stage"' EXIT
mkdir -p "$stage/quickshell/theme/fonts"
cp "$src"/quickshell/*.qml "$src"/quickshell/*.js "$stage/quickshell/"
cp "$src/hyprland.lua" "$stage/"

if [[ -f "$generated/colors.json" ]]; then
  cp "$generated/colors.json" "$stage/quickshell/theme/"
else
  printf 'warning: no %s; the greeter uses its fallback colors\n' "$generated/colors.json" >&2
fi
font="$(fc-match 'Google Sans Flex' --format='%{file}')"
if [[ "$font" == *GoogleSansFlex* ]]; then
  cp "$font" "$stage/quickshell/theme/fonts/title.ttf"
else
  printf 'warning: Google Sans Flex not found; the greeter falls back to a system font\n' >&2
fi
display_name="${name:-$(getent passwd "$USER" | cut -d: -f5 | cut -d, -f1)}"
# The clock follows the shell's time format (config.json time.format).
shell_config="${XDG_CONFIG_HOME:-$HOME/.config}/illogical-impulse/config.json"
python3 - "$USER" "$display_name" "$shell_config" >"$stage/quickshell/theme/user.json" <<'PY'
import json, sys
name, display_name, config_path = sys.argv[1:4]
user = {"name": name, "displayName": display_name or name}
try:
    with open(config_path, encoding="utf-8") as config:
        user["timeFormat"] = json.load(config)["time"]["format"]
except (OSError, KeyError, TypeError, json.JSONDecodeError) as error:
    print(f"warning: no time format from {config_path} ({error}); the greeter uses HH:mm", file=sys.stderr)
print(json.dumps(user))
PY
# Avatar: --avatar, else ~/.face, else the picture SDDM showed.
if [[ -z "$avatar" ]]; then
  for candidate in "$HOME/.face" "/usr/share/sddm/faces/$USER.face.icon"; do
    if [[ -f "$candidate" ]]; then
      avatar="$candidate"
      break
    fi
  done
fi
if [[ -n "$avatar" ]]; then
  # Square crop at 2x the largest size drawn (104 px), as SDDM's change_avatar.sh does.
  magick "$avatar" -gravity center -crop 1:1 +repage -resize 256x256 "png:$stage/quickshell/theme/avatar"
fi
[[ -n "$wallpaper" ]] && cp "$wallpaper" "$stage/quickshell/theme/wallpaper"

printf 'Will install:\n'
(cd "$stage" && find . -type f | sort | sed 's#^\./#  /etc/greetd/#')
printf '  /etc/greetd/config.toml\n  /etc/pam.d/greetd\n'
if $dry_run; then
  printf 'Dry run: nothing written.\n'
  exit 0
fi

# Keep the distribution's files once, so the change can be undone.
for file in /etc/greetd/config.toml /etc/pam.d/greetd; do
  if [[ -f "$file" && ! -f "$file.pre-ii" ]]; then
    sudo cp -a -- "$file" "$file.pre-ii"
    printf 'Backed up %s to %s.pre-ii\n' "$file" "$file"
  fi
done
sudo rm -rf -- /etc/greetd/quickshell
sudo install -d -m 0755 /etc/greetd
sudo cp -r -- "$stage/quickshell" /etc/greetd/quickshell
sudo install -m 0644 -- "$stage/hyprland.lua" /etc/greetd/hyprland.lua
sudo install -m 0644 -- "$src/greetd/config.toml" /etc/greetd/config.toml
sudo install -m 0644 -- "$src/greetd/pam.d/greetd" /etc/pam.d/greetd
sudo chown -R root:root /etc/greetd/quickshell
sudo chmod -R u=rwX,go=rX /etc/greetd/quickshell
printf 'Installed. greetd is not enabled; follow docs/greeter.md to test and switch.\n'
