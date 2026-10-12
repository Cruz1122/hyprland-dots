#!/usr/bin/env bash

set -u
set -o pipefail

image="${1:-}"

notify() {
    if command -v notify-send >/dev/null 2>&1; then
        notify-send "$@"
    fi
}

if [[ -z "$image" || ! -r "$image" ]]; then
    notify "QR scanner" "No se pudo leer la captura seleccionada" \
        -a "Illogical Impulse" -u normal
    exit 2
fi

qr="$(zbarimg --quiet --raw -Sdisable -Sqrcode.enable "$image" 2>/dev/null | head -n 1)"

if [[ -z "$qr" ]]; then
    notify "QR scanner" "No se detectó ningún código QR" \
        -a "Illogical Impulse" -u normal
    exit 4
fi

printf '%s' "$qr" | wl-copy || {
    notify "QR scanner" "El QR fue detectado, pero no se pudo copiar" \
        -a "Illogical Impulse" -u critical
    exit 1
}

if [[ "$qr" =~ ^https?:// ]]; then
    xdg-open "$qr" >/dev/null 2>&1 &
    notify "QR scanner" "Enlace abierto y copiado al portapapeles" \
        -a "Illogical Impulse" -u normal
else
    notify "QR scanner" "Contenido copiado al portapapeles" \
        -a "Illogical Impulse" -u normal
fi
