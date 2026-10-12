#!/usr/bin/env bash
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
dry_run=0
yes=0
skip_deps=0
replace_user=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) dry_run=1 ;;
    --yes) yes=1 ;;
    --skip-deps) skip_deps=1 ;;
    --replace-user) replace_user=1 ;;
    --help|-h)
      printf 'Usage: ./install.sh [--dry-run] [--yes] [--skip-deps] [--replace-user]\n'
      exit 0 ;;
    *) printf 'Unknown option: %s\n' "$arg" >&2; exit 2 ;;
  esac
done
command -v python3 >/dev/null || { printf 'Install Python first: sudo pacman -Syu python\n' >&2; exit 1; }
args=()
(( replace_user == 0 )) || args+=(--replace-user)
if (( dry_run )); then
  printf 'Dry run: no downloads, packages, backups or session changes.\n'
  (( skip_deps )) || printf 'Would install reviewed Arch dependencies, build pinned Quickshell if needed, and prepare Python 3.12 venv.\n'
  python3 "$root/scripts/dotsctl.py" install --dry-run "${args[@]}"
  exit
fi
source /etc/os-release
case "$ID" in arch|cachyos) ;; *) printf 'Supported systems: Arch and CachyOS only.\n' >&2; exit 1 ;; esac
(( EUID != 0 )) || { printf 'Run as your desktop user, not root.\n' >&2; exit 1; }
printf 'Install desktop config; preserve existing custom/ and settings; never delete extra files.\n'
printf 'Existing config is backed up privately before changes. No automatic rollback or session restart.\n'
if (( ! skip_deps )); then
  printf 'Dependencies may require a full system upgrade, AUR builds and sudo. Review packaging/arch first.\n'
fi
if (( ! yes )); then
  read -r -p 'Continue? [y/N] ' answer
  [[ "$answer" == y || "$answer" == Y ]] || exit 1
fi
# Preflight destinations before changing packages or making backups.
python3 "$root/scripts/dotsctl.py" install --dry-run "${args[@]}"
python3 "$root/scripts/dotsctl.py" backup --yes
if (( ! skip_deps )); then
  bash "$root/scripts/install-deps.sh"
fi
python3 "$root/scripts/dotsctl.py" install --yes "${args[@]}"
printf '\nDone. Select Hyprland at your next login when YOU are ready.\n'
printf 'Keep this clone as your source of truth. Capture edits with scripts/dotsctl.py capture --yes.\n'
