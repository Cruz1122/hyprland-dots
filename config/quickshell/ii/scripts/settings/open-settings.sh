#!/usr/bin/env bash
# Open the settings app as a single instance, optionally at a page/setting.
#
# Usage: open-settings.sh [pageId [settingKey]]
#
# A running instance receives `settingsApp open/reveal` over Quickshell IPC
# and its window is focused; otherwise a new instance is started with
# II_SETTINGS_PAGE / II_SETTINGS_KEY set.
#
# Exit codes: 0 success, 1 IPC call to the running instance failed,
# 2 invalid usage. When a new instance is started, qs's own status applies.
#
# Environment: II_SETTINGS_QML overrides the settings entry point
# (default: ~/.config/quickshell/${qsConfig:-ii}/settings.qml).
set -euo pipefail

usage() {
    printf 'Usage: %s [pageId [settingKey]]\n' "${0##*/}" >&2
    exit 2
}

is_valid_id() {
    [[ "$1" =~ ^[A-Za-z0-9._-]+$ ]]
}

(( $# <= 2 )) || usage
page_id="${1:-}"
setting_key="${2:-}"
if [[ $# -ge 1 ]] && ! is_valid_id "$page_id"; then
    printf 'open-settings: invalid pageId: %q\n' "$page_id" >&2
    usage
fi
if [[ $# -ge 2 ]] && ! is_valid_id "$setting_key"; then
    printf 'open-settings: invalid settingKey: %q\n' "$setting_key" >&2
    usage
fi

settings_qml="${II_SETTINGS_QML:-$HOME/.config/quickshell/${qsConfig:-ii}/settings.qml}"

# `qs list -j` prints plain text (exit 0) when nothing runs, so a failed JSON
# parse also means "no instance".
instance_pid="$(qs -p "$settings_qml" list -j 2>/dev/null \
    | jq -r 'if type == "array" then (.[0].pid // empty) else empty end' 2>/dev/null || true)"

if [[ ! "$instance_pid" =~ ^[0-9]+$ ]]; then
    if [[ -n "$page_id" ]]; then
        export II_SETTINGS_PAGE="$page_id"
    fi
    if [[ -n "$setting_key" ]]; then
        export II_SETTINGS_KEY="$setting_key"
    fi
    exec qs -p "$settings_qml"
fi

if [[ -n "$page_id" ]]; then
    qs -p "$settings_qml" ipc call settingsApp open "$page_id" >/dev/null || exit 1
fi
if [[ -n "$setting_key" ]]; then
    qs -p "$settings_qml" ipc call settingsApp reveal "$setting_key" >/dev/null || exit 1
fi

# Focus by the instance's pid rather than the window title, which the app may
# change. Focus is best effort: the page has already been opened.
if command -v hyprctl >/dev/null 2>&1; then
    address="$(hyprctl clients -j 2>/dev/null \
        | jq -r --argjson pid "$instance_pid" 'first(.[] | select(.pid == $pid) | .address) // empty' 2>/dev/null || true)"
    if [[ "$address" =~ ^0x[0-9a-fA-F]+$ ]]; then
        provider="$(hyprctl systeminfo 2>/dev/null | awk -F': *' '$1 == "configProvider" { print $2; exit }' || true)"
        if [[ "$provider" == "lua" ]]; then
            hyprctl dispatch "hl.dsp.focus({ window = \"address:${address}\" })" >/dev/null 2>&1 || true
        else
            hyprctl dispatch focuswindow "address:${address}" >/dev/null 2>&1 || true
        fi
    fi
fi
