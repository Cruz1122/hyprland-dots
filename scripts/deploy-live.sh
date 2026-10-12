#!/usr/bin/env bash
set -euo pipefail
# Compatibility entry point: safe config-only installation, no package changes.
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
exec python3 "$root/scripts/dotsctl.py" install "$@"
