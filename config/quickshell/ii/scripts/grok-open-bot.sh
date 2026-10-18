#!/usr/bin/env bash
set -u

bot_id="${1:-}"
if [[ ! "$bot_id" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$ ]]; then
    exit 2
fi

# Grok Bot 0.71.2 exposes the agent route as the supported deep link for a
# bot conversation. It focuses that bot in the app; the app does not expose a
# public message-id route for the roster's lastMessageId/newestEntryId fields.
command -v xdg-open >/dev/null 2>&1 || exit 1
deep_link="grokbot://app/v1/agent?id=${bot_id}"

workspace=""
window_address=""
window_workspace=""
if command -v hyprctl >/dev/null 2>&1; then
    hypr_config_provider="$(hyprctl systeminfo 2>/dev/null | awk -F': *' '$1 == "configProvider" { print $2; exit }')"

    hypr_focus_window() {
        if [[ "$hypr_config_provider" == "lua" ]]; then
            hyprctl dispatch "hl.dsp.focus({ window = \"address:${1}\" })"
        else
            hyprctl dispatch focuswindow "address:${1}"
        fi
    }

    hypr_move_window() {
        if [[ "$hypr_config_provider" == "lua" ]]; then
            hyprctl dispatch "hl.dsp.window.move({ workspace = \"${1}\", follow = false, window = \"address:${2}\" })"
        else
            hyprctl dispatch movetoworkspace "${1},address:${2}"
        fi
    }

    workspace="$(hyprctl activeworkspace -j 2>/dev/null | python3 -c 'import json,sys; data=json.load(sys.stdin); print(data.get("name", data.get("id", "")))' 2>/dev/null || true)"
    if [[ ! "$workspace" =~ ^[A-Za-z0-9_.:+-]+$ ]]; then
        workspace=""
    fi

    client_info="$(hyprctl clients -j 2>/dev/null | ACTIVE_WORKSPACE="$workspace" python3 -c '
import json, os, sys
try:
    clients = json.load(sys.stdin)
except Exception:
    clients = []
active = os.environ.get("ACTIVE_WORKSPACE", "")
matching = []
for client in clients:
    classes = {str(client.get(key, "")).lower() for key in ("class", "initialClass", "app_id", "initialAppId")}
    if "grok-bot" not in classes:
        continue
    address = str(client.get("address", ""))
    workspace = client.get("workspace", {})
    workspace_name = str(workspace.get("name", "")) if isinstance(workspace, dict) else ""
    matching.append((address, workspace_name))
matching.sort(key=lambda item: (item[1] != active, item[1] == "special:grok-bot"))
if matching:
    print("\t".join(matching[0]))
' 2>/dev/null || true)"
    IFS=$'\t' read -r window_address window_workspace <<< "$client_info"
fi

# Hand the bot deep link to Grok Bot's registered single-instance handler. Keep
# this asynchronous so a warm instance can be focused without waiting on xdg-open.
xdg-open "$deep_link" >/dev/null 2>&1 </dev/null &

if [[ "$window_address" =~ ^0x[0-9a-fA-F]+$ ]]; then
    if [[ "$window_workspace" == "special:grok-bot" && -n "$workspace" ]]; then
        hypr_move_window "$workspace" "$window_address" >/dev/null 2>&1 || true
    fi
    hypr_focus_window "$window_address" >/dev/null 2>&1 || true
    exit 0
fi

# Only wait for a client when Grok Bot was not already running. Normal
# notifications use the existing window path above and return immediately.
if ! command -v hyprctl >/dev/null 2>&1 || [[ -z "$workspace" ]]; then
    exit 0
fi

for _ in {1..24}; do
    client_info="$(hyprctl clients -j 2>/dev/null | python3 -c '
import json, sys
try:
    clients = json.load(sys.stdin)
except Exception:
    clients = []
for client in clients:
    classes = {str(client.get(key, "")).lower() for key in ("class", "initialClass", "app_id", "initialAppId")}
    if "grok-bot" in classes:
        item = client.get("workspace", {})
        workspace = str(item.get("name", "")) if isinstance(item, dict) else ""
        print(str(client.get("address", "")) + "\t" + workspace)
        break
' 2>/dev/null || true)"
    IFS=$'\t' read -r window_address window_workspace <<< "$client_info"
    if [[ "$window_address" =~ ^0x[0-9a-fA-F]+$ ]]; then
        if [[ "$window_workspace" == "special:grok-bot" ]]; then
            hypr_move_window "$workspace" "$window_address" >/dev/null 2>&1 || true
        fi
        hypr_focus_window "$window_address" >/dev/null 2>&1 || true
        exit 0
    fi
    sleep 0.1
done

# xdg-open has already received the deep link. If the app starts slowly, leave
# its final placement to Hyprland instead of repeatedly stealing focus.
exit 0
