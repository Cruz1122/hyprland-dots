#!/usr/bin/env bash
set -u

app_image="${HOME}/.local/share/grok-bot/appimage"
if [[ ! -x "$app_image" ]]; then
    exit 0
fi

# Do not relaunch a session that the user intentionally closed.  Hyprland
# launch rules below apply only to this startup invocation.
if command -v pgrep >/dev/null 2>&1 && pgrep -f -- "$app_image" >/dev/null 2>&1; then
    exit 0
fi

exec "$app_image" >/dev/null 2>&1
