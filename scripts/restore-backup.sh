#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/restore-backup.sh BACKUP_DIR [--dry-run] [--yes]
       scripts/restore-backup.sh --latest [--dry-run] [--yes]

Restore live illogical-impulse config paths from a backup.

Options:
  --latest   Restore from ~/.local/state/illogical-impulse/backups/latest.
  --dry-run  Show what would change without modifying files.
  --yes      Required for a real restore because rsync --delete is destructive.
  --help     Show this help.
EOF
}

backup_root=""
dry_run=0
yes=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --latest) backup_root="$HOME/.local/state/illogical-impulse/backups/latest" ;;
    --dry-run) dry_run=1 ;;
    --yes) yes=1 ;;
    --help|-h) usage; exit 0 ;;
    --*) printf 'Unknown argument: %s\n\n' "$1" >&2; usage >&2; exit 2 ;;
    *)
      if [[ -n "$backup_root" ]]; then
        printf 'Only one backup directory may be provided.\n' >&2
        exit 2
      fi
      backup_root="$1"
      ;;
  esac
  shift
done

if [[ -z "$backup_root" ]]; then
  usage >&2
  exit 2
fi

if (( ! dry_run && ! yes )); then
  printf 'Refusing destructive restore without --yes. Run --dry-run first.\n' >&2
  exit 2
fi

backup_root="$(readlink -f "$backup_root" 2>/dev/null || true)"

if [[ ! -d "$backup_root" ]]; then
  printf 'Backup directory not found: %s\n' "$backup_root" >&2
  exit 1
fi

for required in quickshell-ii hypr illogical-impulse; do
  if [[ ! -d "$backup_root/$required" ]]; then
    printf 'Backup is missing required directory: %s\n' "$backup_root/$required" >&2
    exit 1
  fi
done

target_quickshell="$HOME/.config/quickshell/ii"
target_hypr="$HOME/.config/hypr"
target_ii="$HOME/.config/illogical-impulse"

for target_dir in "$target_quickshell" "$target_hypr" "$target_ii"; do
  if [[ ! -d "$target_dir" ]]; then
    printf 'Target directory not found, refusing restore: %s\n' "$target_dir" >&2
    exit 1
  fi
done

if [[ -f "$backup_root/checksums.sha256" ]]; then
  (cd "$backup_root" && sha256sum -c checksums.sha256 >/dev/null)
else
  printf 'Backup has no checksums.sha256, refusing restore: %s\n' "$backup_root" >&2
  exit 1
fi

timestamp="$(date '+%Y%m%d-%H%M%S')"
pre_restore_root="$HOME/.local/state/illogical-impulse/backups/pre-restore-$timestamp"
lock_dir="$HOME/.local/state/illogical-impulse/deploy.lock"

make_checksums() {
  local root="$1"
  (cd "$root" && python - <<'PY'
from pathlib import Path
import hashlib

root = Path('.')
checksum_file = Path('checksums.sha256')
with checksum_file.open('w', encoding='utf-8') as out:
    for path in sorted(p for p in root.rglob('*') if p.is_file() and p != checksum_file):
        h = hashlib.sha256()
        with path.open('rb') as file_obj:
            for chunk in iter(lambda: file_obj.read(1024 * 1024), b''):
                h.update(chunk)
        out.write(f"{h.hexdigest()}  {path.as_posix()}\n")
PY
  )
}

cleanup_lock() {
  if (( ! dry_run )); then
    rmdir "$lock_dir" 2>/dev/null || true
  fi
}

if (( ! dry_run )); then
  if ! mkdir "$lock_dir"; then
    printf 'Another deploy or restore appears to be running: %s\n' "$lock_dir" >&2
    exit 1
  fi
  trap cleanup_lock EXIT

  pre_restore_root="$(mktemp -d "${pre_restore_root}.XXXXXXXX")"
  rsync -a "$target_quickshell/" "$pre_restore_root/quickshell-ii/"
  rsync -a "$target_hypr/" "$pre_restore_root/hypr/"
  rsync -a "$target_ii/" "$pre_restore_root/illogical-impulse/"
  {
    printf 'backup_timestamp=%s\n' "$timestamp"
    printf 'backup_reason=pre-restore\n'
    printf 'restore_source=%s\n' "$backup_root"
  } > "$pre_restore_root/metadata.txt"
  make_checksums "$pre_restore_root"
  ln -sfn "$pre_restore_root" "$HOME/.local/state/illogical-impulse/backups/latest"
  printf 'Pre-restore backup: %s. No automatic rollback on failure.\n' "$pre_restore_root"
fi

copy_cmd=(rsync -a --delete)
config_excludes=(
  --exclude 'installed_listfile'
  --exclude 'installed_true'
)
if (( dry_run )); then
  copy_cmd+=(--dry-run --itemize-changes)
fi

"${copy_cmd[@]}" "$backup_root/quickshell-ii/" "$target_quickshell/"
"${copy_cmd[@]}" "$backup_root/hypr/" "$target_hypr/"
"${copy_cmd[@]}" "${config_excludes[@]}" "$backup_root/illogical-impulse/" "$target_ii/"

if (( dry_run )); then
  printf 'Dry-run complete. No files changed.\n'
else
  printf 'Restored live config from: %s\nPre-restore backup: %s\n' "$backup_root" "$pre_restore_root"
fi
