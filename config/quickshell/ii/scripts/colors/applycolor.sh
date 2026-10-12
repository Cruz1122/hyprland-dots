#!/usr/bin/env bash

QUICKSHELL_CONFIG_NAME="ii"
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
CONFIG_DIR="$XDG_CONFIG_HOME/quickshell/$QUICKSHELL_CONFIG_NAME"
CACHE_DIR="$XDG_CACHE_HOME/quickshell"
STATE_DIR="$XDG_STATE_HOME/quickshell"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MATERIAL_COLORS_FILE="$STATE_DIR/user/generated/material_colors.scss"

term_alpha=100 #Set this to < 100 make all your terminals transparent
# sleep 0 # idk i wanted some delay or colors dont get applied properly
if [ ! -d "$STATE_DIR"/user/generated ]; then
  mkdir -p "$STATE_DIR"/user/generated
fi
cd "$CONFIG_DIR" || exit

if [ ! -s "$MATERIAL_COLORS_FILE" ]; then
  echo "[applycolor.sh] Generated color palette is missing or empty; keeping existing terminal colors." >&2
  exit 0
fi

colorlist=()
colorvalues=()
color_pattern='^(\$[[:alnum:]_]+):[[:space:]]+(#[[:xdigit:]]{6});$'

while IFS= read -r color_line; do
  if [[ $color_line =~ $color_pattern ]]; then
    colorlist+=("${BASH_REMATCH[1]}")
    colorvalues+=("${BASH_REMATCH[2]}")
  fi
done < "$MATERIAL_COLORS_FILE"

render_color_template() {
  local template_path="$1"
  local destination_path="$2"
  local alpha_value="${3:-}"
  local temporary_path

  temporary_path=$(mktemp "${destination_path}.tmp.XXXXXX") || return 1
  if ! cp -- "$template_path" "$temporary_path"; then
    rm -f -- "$temporary_path"
    return 1
  fi

  for i in "${!colorlist[@]}"; do
    if ! sed -i "s/${colorlist[$i]} #/${colorvalues[$i]#\#}/g" "$temporary_path"; then
      rm -f -- "$temporary_path"
      return 1
    fi
  done

  if [ -n "$alpha_value" ]; then
    if [[ ! $alpha_value =~ ^[0-9]{1,3}$ ]] || (( alpha_value > 100 )); then
      echo "[applycolor.sh] Invalid terminal opacity; keeping existing terminal colors." >&2
      rm -f -- "$temporary_path"
      return 1
    fi
    if ! sed -i "s/\$alpha/$alpha_value/g" "$temporary_path"; then
      rm -f -- "$temporary_path"
      return 1
    fi
  fi

  if grep -qE '#\$[[:alnum:]_]+ #' "$temporary_path"; then
    echo "[applycolor.sh] Palette is incomplete; keeping existing terminal colors." >&2
    rm -f -- "$temporary_path"
    return 1
  fi

  if ! mv -- "$temporary_path" "$destination_path"; then
    rm -f -- "$temporary_path"
    return 1
  fi
}

apply_kitty() {  
  # Check if terminal escape sequence template exists
  if [ ! -r "$SCRIPT_DIR/terminal/kitty-theme.conf" ]; then
    echo "Template file not found for Kitty theme. Skipping that."
    return
  fi
  # Render template atomically so an incomplete palette cannot corrupt Kitty.
  mkdir -p "$STATE_DIR"/user/generated/terminal || return 1
  if ! render_color_template \
    "$SCRIPT_DIR/terminal/kitty-theme.conf" \
    "$STATE_DIR/user/generated/terminal/kitty-theme.conf"; then
    return 1
  fi

  # Reload
  local kitty_pids_output
  local kitty_pids=()
  if ! kitty_pids_output=$(pidof kitty) || [ -z "$kitty_pids_output" ]; then
    return
  fi
  read -r -a kitty_pids <<< "$kitty_pids_output"
  kill -SIGUSR1 "${kitty_pids[@]}"
}

apply_anyterm() {
  # Check if terminal escape sequence template exists
  if [ ! -r "$SCRIPT_DIR/terminal/sequences.txt" ]; then
    echo "Template file not found for Terminal. Skipping that."
    return
  fi
  # Render template atomically so incomplete escape sequences are never applied.
  mkdir -p "$STATE_DIR"/user/generated/terminal || return 1
  if ! render_color_template \
    "$SCRIPT_DIR/terminal/sequences.txt" \
    "$STATE_DIR/user/generated/terminal/sequences.txt" \
    "$term_alpha"; then
    return 1
  fi

  for file in /dev/pts/*; do
    if [[ $file =~ ^/dev/pts/[0-9]+$ ]]; then
      {
      cat "$STATE_DIR"/user/generated/terminal/sequences.txt >"$file"
      } & disown || true
    fi
  done
}

apply_term() {
  apply_anyterm &
  apply_kitty &
}

main() {
  local config_file="$XDG_CONFIG_HOME/illogical-impulse/config.json"
  local enable_terminal

  # Check if terminal theming is enabled in config.
  if [ -f "$config_file" ]; then
    enable_terminal=$(jq -r '.appearance.wallpaperTheming.enableTerminal' "$config_file")
    if [ "$enable_terminal" = "true" ]; then
      apply_term &
    fi
  else
    echo "Config file not found at $config_file. Applying terminal theming by default."
    apply_term &
  fi
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  main "$@"
fi

# apply_qt & # Qt theming is already handled by kde-material-colors
