#!/usr/bin/env bash

set -euo pipefail
umask 077

if [[ $# -ne 3 ]]; then
    exit 2
fi

image=$1
python=$2
parser=$3
[[ "$image" = /* && -f "$image" && -r "$image" && -x "$python" && -r "$parser" ]] || exit 2

file_size=$(stat -c '%s' -- "$image") || exit 2
[[ "$file_size" =~ ^[0-9]{1,9}$ ]] || exit 2
(( file_size > 0 && file_size <= 26214400 )) || exit 3

dimensions=$(timeout 5s magick identify -format '%w %h' "$image" 2>/dev/null) || exit 2
read -r width height <<< "$dimensions"
[[ "$width" =~ ^[0-9]{1,5}$ && "$height" =~ ^[0-9]{1,5}$ ]] || exit 2
(( width > 0 && height > 0 && width <= 10000 && height <= 10000 && width * height <= 50000000 )) || exit 3

script_dir=$(dirname -- "$0")
exec /usr/bin/bash "$script_dir/authenticator-capture-qr.sh" \
    "$image" "$python" "$parser" 0 0 "$width" "$height"
