#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 1 ]]; then
    exit 2
fi

backup=$1
[[ "$backup" = /* && -f "$backup" && -r "$backup" ]] || exit 2
file_size=$(stat -c '%s' -- "$backup") || exit 2
[[ "$file_size" =~ ^[0-9]{1,9}$ ]] || exit 2
(( file_size > 0 && file_size <= 5242880 )) || exit 3

exec /usr/bin/cat -- "$backup"
