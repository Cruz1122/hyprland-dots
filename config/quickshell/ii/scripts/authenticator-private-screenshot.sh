#!/usr/bin/env bash

set -euo pipefail
umask 077

if [[ $# -ne 3 ]]; then
    exit 2
fi

screen=$1
directory=$2
image=$3
[[ -n "$screen" && -n "$directory" && -n "$image" ]] || exit 2

mkdir -p -- "$directory"
if [[ -e "$image" ]]; then
    chmod 600 -- "$image"
fi
grim -o "$screen" "$image"
chmod 600 -- "$image"
