#!/usr/bin/env bash

set -euo pipefail
umask 077

if [[ $# -ne 7 ]]; then
    exit 2
fi

image=$1
python=$2
parser=$3
x=$4
y=$5
width=$6
height=$7

[[ -r "$image" && -x "$python" && -r "$parser" ]] || exit 2

crop=""
binarized=""
cleanup() {
    [[ -z "$crop" ]] || rm -f -- "$crop"
    [[ -z "$binarized" ]] || rm -f -- "$binarized"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

if [[ ! "$x" =~ ^[0-9]{1,6}$ || ! "$y" =~ ^[0-9]{1,6}$ || ! "$width" =~ ^[0-9]{1,6}$ || ! "$height" =~ ^[0-9]{1,6}$ ]]; then
    exit 2
fi
(( width > 0 && height > 0 )) || exit 2
crop=$(mktemp "${TMPDIR:-/tmp}/illogical-authenticator-qr.XXXXXXXX.png")
timeout 10s magick "$image" -crop "${width}x${height}+${x}+${y}" +repage "$crop" >/dev/null 2>&1 || exit 2
status=0
output=$(timeout 10s "$python" "$parser" qr "$crop" 2>/dev/null) || status=$?
if [[ $status -eq 0 ]]; then
    printf '%s' "$output"
    exit 0
fi
[[ $status -eq 1 ]] || exit "$status"
# Screen captures sometimes render QR codes with soft, scaled edges that the
# scanner cannot read directly; retry once on a binarized copy.
binarized=$(mktemp "${TMPDIR:-/tmp}/illogical-authenticator-qr.XXXXXXXX.png")
timeout 10s magick "$crop" -colorspace Gray -auto-threshold OTSU "$binarized" >/dev/null 2>&1 || exit 2
timeout 10s "$python" "$parser" qr "$binarized" 2>/dev/null
