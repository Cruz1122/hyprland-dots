#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

bash -n scripts/deploy-live.sh
bash -n scripts/restore-backup.sh
bash -n install.sh
bash -n scripts/install-deps.sh
bash -n scripts/rebuild-quickshell.sh
bash -n config/quickshell/ii/scripts/colors/applycolor.sh
bash -n config/quickshell/ii/scripts/colors/switchwall.sh
bash -n config/quickshell/ii/scripts/videos/record.sh
bash -n config/quickshell/ii/scripts/grok-open-bot.sh
bash -n config/quickshell/ii/scripts/grok-start-hidden.sh
bash -n scripts/settings-harness/run.sh
bash -n config/quickshell/ii/scripts/settings/open-settings.sh
python -m py_compile scripts/settings-harness/summarize.py tests/test_settings_harness.py
python -m py_compile config/quickshell/ii/scripts/settings/idlegen.py config/quickshell/ii/scripts/settings/monitorsgen.py tests/test_idlegen.py tests/test_monitorsgen.py
python -m py_compile config/quickshell/ii/scripts/hyprland/hyprconfigurator.py tests/test_hyprconfigurator.py
python -m py_compile config/quickshell/ii/scripts/settings/default-apps.py tests/test_default_apps.py
python -m py_compile config/quickshell/ii/scripts/settings/animationsgen.py tests/test_animationsgen.py tests/test_animations_hyprland_verify.py tests/test_animation_backend.py
python -m py_compile tests/test_record_script.py tests/test_open_settings.py tests/test_main_shell_ipc_contract.py
python -m py_compile config/quickshell/ii/scripts/grok-roster.py tests/test_grok_roster.py tests/test_grok_open_bot.py
python -m py_compile scripts/settingsctl.py tests/test_settingsctl.py tests/test_screen_recording_contract.py tests/test_terminal_colors.py
python -m py_compile tests/test_settings_contract.py tests/test_settings_qml.py
python -m py_compile config/quickshell/ii/scripts/settings/hyprbase.py tests/test_hyprbase.py tests/test_hyprland_base.py
python -m unittest discover -s tests -p 'test_*.py'
if command -v node >/dev/null 2>&1 && test -f tests/browser-extension.test.mjs; then
    node --test tests/browser-extension.test.mjs tests/browser-extension-background.test.mjs
fi
# Deployment/capture/dry-run are tested with isolated temporary homes, not live state.
scripts/settingsctl.py validate config/illogical-impulse/config.json >/dev/null
scripts/settingsctl.py migrate config/illogical-impulse/config.json --dry-run >/dev/null

# Offscreen settings harness (sandboxed, never touches the live session).
# Exit 77 means a required tool (bwrap, qs, ...) is missing: skipped, not passed.
run_harness() {
    local status=0
    scripts/settings-harness/run.sh "$@" || status=$?
    if ((status == 77)); then
        printf 'SKIPPED: settings harness %s (missing tool, see the SKIP line above)\n' "$*"
    elif ((status != 0)); then
        exit "$status"
    fi
}
# Main run with the fake hyprctl, so the Hyprland rows render available.
run_harness --strict --discard --hyprland-stub
# Without Hyprland: every Hyprland row renders its unavailable state.
run_harness --strict --discard --sizes 1100x760
run_harness --strict --discard --allow-config-writes --hyprland-stub --sizes 1100x760 --driver tests/harness/settings-interact.qml

printf 'Verification passed.\n'
