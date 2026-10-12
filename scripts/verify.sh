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
python -m py_compile scripts/settingsctl.py tests/test_settingsctl.py tests/test_settings_foundation_contract.py tests/test_screen_recording_contract.py tests/test_terminal_colors.py
python -m unittest discover -s tests -p 'test_*.py'
# Deployment/capture/dry-run are tested with isolated temporary homes, not live state.
scripts/settingsctl.py validate config/illogical-impulse/config.json >/dev/null
scripts/settingsctl.py migrate config/illogical-impulse/config.json --dry-run >/dev/null

printf 'Verification passed.\n'
