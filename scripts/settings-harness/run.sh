#!/usr/bin/env bash
# Offscreen render harness for the Quickshell settings app.
#
# Copies config/quickshell/ii into a temporary tree, replaces services that
# need a compositor with inert stubs, seeds private XDG directories and renders
# the requested settings pages inside a read-only bubblewrap sandbox: no
# network, no live Wayland/Hyprland/PipeWire/D-Bus sockets, and a private
# session bus without service activation. The only live resource exposed is
# the Xwayland socket (read-only bind) that the GPU renderer needs for a GLX
# context; nothing is ever mapped on screen. With --hyprland-stub, a fake
# hyprctl (tests/harness/stubs/hyprctl) answers from fixtures so the Hyprland
# rows render available; the real Hyprland is never contacted.
#
# Exit status: 0 pass, 1 failure, 2 usage error, 77 skipped (missing tool).
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: scripts/settings-harness/run.sh [options]

  --out DIR         Output directory (default: a new mktemp dir under $TMPDIR)
  --sizes LIST      Comma-separated WIDTHxHEIGHT list (default: 760x720,1100x760,1600x900)
  --pages LIST      Comma-separated page ids or indices (default: every page)
  --renderer MODE   auto | gpu | software (default: auto)
  --config FILE     config.json to seed (default: the repository default config);
                    'none' starts without one, so the app writes its schema defaults
  --shell DIR       Shell tree to test (default: config/quickshell/ii of this repository)
  --driver FILE     QML driver to run instead of tests/harness/settings-shot.qml
  --env NAME=VALUE  Extra environment variable for the app (repeatable)
  --settle MS       Delay before each capture (default: 900)
  --timeout SEC     Kill the app after SEC seconds (default: 300)
  --hyprland-stub   Put a fake hyprctl (tests/harness/stubs/hyprctl, answers from fixtures) first
                    on PATH, set HYPRLAND_INSTANCE_SIGNATURE=settings-harness and seed the
                    sandbox config with copies of config/hypr/hyprland.lua and its base files;
                    its calls are logged to <out>/hyprctl.log. --env PATH=... still wins.
  --strict          Fail on app warnings, row overlaps/overflow, open popups, config.json
                    writes and writes to hypr/custom/* or hypr/monitors.lua
  --allow-config-writes
                    With --strict, report those writes instead of failing (interaction drivers)
  --keep            Keep the temporary shell copy and XDG directories
  --discard         Delete the output directory when the run passes
  -h, --help        Show this help

Outputs (in the output directory): <W>x<H>/<NN>-<page>.png screenshots,
harness.log, report.json, config.before.json, config.after.json,
hypr.before.json and hypr.after.json (sha256 of hypr/custom/* and
hypr/monitors.lua), and hyprctl.log with --hyprland-stub.
EOF
}

die() {
    printf 'settings-harness: %s\n' "$*" >&2
    exit 2
}

skip() {
    printf 'SKIP: %s\n' "$*" >&2
    exit 77
}

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/../.." && pwd)"
shell_src="$repo_root/config/quickshell/ii"
harness_src="$repo_root/tests/harness"

out=""
sizes="760x720,1100x760,1600x900"
pages=""
renderer="auto"
config_src="$repo_root/config/illogical-impulse/config.json"
driver="$harness_src/settings-shot.qml"
settle=900
timeout_s=300
strict=0
allow_writes=0
hypr_stub=0
keep=0
discard=0
extra_env=()

while (($#)); do
    case "$1" in
        --out) out="${2:?--out needs a value}"; shift 2 ;;
        --sizes) sizes="${2:?--sizes needs a value}"; shift 2 ;;
        --pages) pages="${2:?--pages needs a value}"; shift 2 ;;
        --renderer) renderer="${2:?--renderer needs a value}"; shift 2 ;;
        --config) config_src="${2:?--config needs a value}"; shift 2 ;;
        --shell) shell_src="${2:?--shell needs a value}"; shift 2 ;;
        --driver) driver="${2:?--driver needs a value}"; shift 2 ;;
        --env)
            [[ "${2:-}" == *=* ]] || die "--env expects NAME=VALUE"
            extra_env+=(--setenv "${2%%=*}" "${2#*=}")
            shift 2
            ;;
        --settle) settle="${2:?--settle needs a value}"; shift 2 ;;
        --timeout) timeout_s="${2:?--timeout needs a value}"; shift 2 ;;
        --strict) strict=1; shift ;;
        --allow-config-writes) allow_writes=1; shift ;;
        --hyprland-stub) hypr_stub=1; shift ;;
        --keep) keep=1; shift ;;
        --discard) discard=1; shift ;;
        -h | --help) usage; exit 0 ;;
        *) usage >&2; die "unknown option: $1" ;;
    esac
done

[[ "$settle" =~ ^[0-9]+$ ]] || die "--settle must be milliseconds"
[[ "$timeout_s" =~ ^[0-9]+$ ]] || die "--timeout must be seconds"
[[ "$config_src" == none || -f "$config_src" ]] || die "config not found: $config_src"
[[ -f "$shell_src/settings.qml" ]] || die "not a shell tree (no settings.qml): $shell_src"
shell_src="$(cd -- "$shell_src" && pwd)"
[[ -f "$driver" ]] || die "driver not found: $driver"
sizes="${sizes// /,}"
IFS=',' read -r -a size_list <<<"$sizes"
for size in "${size_list[@]}"; do
    [[ "$size" =~ ^[0-9]+x[0-9]+$ ]] || die "invalid size: $size"
done

for tool in bwrap qs dbus-run-session timeout tar python3; do
    command -v "$tool" >/dev/null 2>&1 || skip "$tool is not installed"
done

x_socket=""
if [[ -n "${DISPLAY:-}" && "$DISPLAY" == :* ]]; then
    display_number="${DISPLAY#:}"
    x_socket="/tmp/.X11-unix/X${display_number%%.*}"
fi
gpu_ready=0
if [[ -d /dev/dri && -n "$x_socket" && -S "$x_socket" ]]; then
    gpu_ready=1
fi
case "$renderer" in
    auto) if ((gpu_ready)); then renderer=gpu; else renderer=software; fi ;;
    gpu) ((gpu_ready)) || skip "GPU renderer needs /dev/dri and a local X socket for DISPLAY" ;;
    software) ;;
    *) die "--renderer must be auto, gpu or software" ;;
esac
if [[ "$renderer" == software ]]; then
    printf 'WARNING: software scene graph: ShaderEffect/OpacityMask (button backgrounds, masks) is not drawn; screenshots are not faithful.\n' >&2
fi

work="$(mktemp -d "${TMPDIR:-/tmp}/settings-harness.XXXXXX")"
if [[ -z "$out" ]]; then
    out="$work/out"
fi
mkdir -p "$out"
out="$(cd -- "$out" && pwd)"

cleanup() {
    if ((keep)); then
        printf 'kept work tree: %s\n' "$work" >&2
    elif [[ "$out" == "$work/out" && -d "$out" ]]; then
        rm -rf -- "$work/ii" "$work/xdg" "$work/home" "$work/hyprctl" "$work/dbus-session.conf"
    else
        rm -rf -- "$work"
    fi
}
trap cleanup EXIT

# Copy of the shell under test. The Grok avatar frames are large and unused by
# the settings app.
mkdir -p "$work/ii"
tar -C "$shell_src" \
    --exclude='./assets/grok-avatar-animations' \
    --exclude='./assets/grok-avatar-animations-interpolated' \
    --exclude='__pycache__' \
    -cf - . | tar -C "$work/ii" -xf -
cp -- "$harness_src/stubs/Idle.qml" "$work/ii/services/Idle.qml"
# Inject settings.qml's qs.* imports where the driver asks for them.
python3 - "$driver" "$shell_src/settings.qml" "$work/ii/harness-driver.qml" <<'PY'
import re
import sys
driver, settings, target = sys.argv[1:]
imports = "\n".join(re.findall(r"^import qs\.[\w.]+.*$", open(settings, encoding="utf-8").read(), re.M))
text = open(driver, encoding="utf-8").read().replace("// @harness-imports", imports, 1)
open(target, "w", encoding="utf-8").write(text)
PY
# The repository may live under /tmp, which the sandbox replaces.
cp -- "$harness_src/dbus-session.conf" "$work/dbus-session.conf"

xdg="$work/xdg"
home="$work/home"
mkdir -p "$xdg/config/illogical-impulse" "$xdg/cache" "$xdg/data" \
    "$xdg/state/quickshell/user/generated" "$home"
if [[ "$config_src" != none ]]; then
    # Same placeholder expansion as scripts/dotsctl.py render().
    python3 - "$config_src" "$xdg/config/illogical-impulse/config.json" "$home" "$xdg/config" <<'PY'
import sys
source, target, home, config = sys.argv[1:]
data = open(source, "rb").read()
data = data.replace(b"@HOME@", home.encode()).replace(b"@CONFIG@", config.encode())
open(target, "wb").write(data)
PY
    cp -- "$xdg/config/illogical-impulse/config.json" "$out/config.before.json"
fi
cp -- "$harness_src/fixtures/colors.json" "$xdg/state/quickshell/user/generated/colors.json"
# The default config points background.wallpaperPath at @CONFIG@/hypr/wallpaper.png.
mkdir -p "$xdg/config/hypr"
cp -- "$repo_root/config/hypr/wallpaper.png" "$xdg/config/hypr/wallpaper.png"
for size in "${size_list[@]}"; do
    mkdir -p "$out/$size"
done
if ((hypr_stub)); then
    # Inside $work: the sandbox replaces /tmp, so files elsewhere vanish.
    mkdir -p "$work/hyprctl/bin" "$work/hyprctl/fixtures"
    cp -- "$harness_src/stubs/hyprctl" "$work/hyprctl/bin/hyprctl"
    chmod 0755 "$work/hyprctl/bin/hyprctl"
    for fixture in hyprland-options.json hyprctl-devices.json hyprctl-monitors-all.json hyprctl-animations.json; do
        cp -- "$repo_root/tests/fixtures/$fixture" "$work/hyprctl/fixtures/$fixture"
    done
    : >"$out/hyprctl.log"
    # Copies of the repository's Hyprland entry point and the base files that
    # come before the app's own files, never the live ~/.config.
    mkdir -p "$xdg/config/hypr/hyprland/lib"
    cp -- "$repo_root/config/hypr/hyprland.lua" "$xdg/config/hypr/hyprland.lua"
    cp -- "$repo_root/config/hypr/hyprland/general.lua" "$repo_root/config/hypr/hyprland/colors.lua" "$xdg/config/hypr/hyprland/"
    cp -- "$repo_root/config/hypr/hyprland/lib/init.lua" "$xdg/config/hypr/hyprland/lib/init.lua"
fi

# sha256 of the Hyprland files the app may write (hypr/custom/*,
# hypr/monitors.lua); --strict fails when one appears or changes.
snapshot_hypr() {
    python3 - "$xdg/config" "$1" <<'PY'
import hashlib
import json
import sys
from pathlib import Path
root, target = Path(sys.argv[1]), Path(sys.argv[2])
files = sorted((root / "hypr/custom").rglob("*")) + [root / "hypr/monitors.lua"]
digests = {str(path.relative_to(root)): hashlib.sha256(path.read_bytes()).hexdigest()
           for path in files if path.is_file()}
target.write_text(json.dumps(digests, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY
}
snapshot_hypr "$out/hypr.before.json"

bwrap_args=(
    --ro-bind / /
    --dev /dev
    --proc /proc
    --tmpfs /tmp
    --tmpfs /run/user
    --tmpfs /run/dbus
    --bind "$work" "$work"
    --bind "$out" "$out"
    --perms 0700 --dir /tmp/rt
    --unshare-net
    --unshare-pid
    --die-with-parent
    --new-session
    --unsetenv WAYLAND_DISPLAY
    --unsetenv DISPLAY
    --unsetenv XAUTHORITY
    --unsetenv HYPRLAND_INSTANCE_SIGNATURE
    --unsetenv HYPRLAND_CMD
    --unsetenv DBUS_SESSION_BUS_ADDRESS
    --unsetenv DBUS_SYSTEM_BUS_ADDRESS
    --unsetenv SSH_AUTH_SOCK
    --unsetenv PIPEWIRE_REMOTE
    --unsetenv PULSE_SERVER
    --unsetenv QS_CONFIG_PATH
    --unsetenv QS_CONFIG_NAME
    --unsetenv QS_MANIFEST
    --unsetenv QT_QPA_PLATFORMTHEME
    --unsetenv QT_STYLE_OVERRIDE
    --setenv HOME "$home"
    --setenv XDG_CONFIG_HOME "$xdg/config"
    --setenv XDG_CACHE_HOME "$xdg/cache"
    --setenv XDG_STATE_HOME "$xdg/state"
    --setenv XDG_DATA_HOME "$xdg/data"
    --setenv XDG_RUNTIME_DIR /tmp/rt
    --setenv QT_QPA_PLATFORM offscreen
    --setenv NO_COLOR 1
    --setenv SHOT_DIR "$out"
    --setenv SHOT_SIZES "$sizes"
    --setenv SHOT_PAGES "$pages"
    --setenv SHOT_SETTLE_MS "$settle"
)
if [[ "$renderer" == gpu ]]; then
    bwrap_args+=(
        --dev-bind /dev/dri /dev/dri
        --ro-bind "$x_socket" "$x_socket"
        --setenv DISPLAY "$DISPLAY"
        --setenv QT_QUICK_BACKEND rhi
        --setenv QSG_RHI_BACKEND opengl
    )
else
    bwrap_args+=(--setenv QT_QUICK_BACKEND software)
fi
if ((hypr_stub)); then
    # Before extra_env, so a test's own --env PATH=<stub> keeps priority.
    bwrap_args+=(
        --setenv PATH "$work/hyprctl/bin:${PATH:-/usr/bin:/bin}"
        --setenv HYPRLAND_INSTANCE_SIGNATURE settings-harness
        --setenv HYPRCTL_LOG "$out/hyprctl.log"
        --setenv HYPRCTL_FIXTURES "$work/hyprctl/fixtures"
    )
fi
bwrap_args+=("${extra_env[@]}")

hyprland_mode=absent
if ((hypr_stub)); then
    hyprland_mode=stub
fi
printf 'settings-harness: renderer=%s sizes=%s pages=%s hyprland=%s\n' "$renderer" "$sizes" "${pages:-all}" "$hyprland_mode" >&2
set +e
bwrap "${bwrap_args[@]}" \
    dbus-run-session --config-file="$work/dbus-session.conf" -- \
    timeout --kill-after=10 "$timeout_s" qs --no-color -p "$work/ii/harness-driver.qml" \
    >"$out/harness.log" 2>&1
status=$?
set -e
cp -- "$xdg/config/illogical-impulse/config.json" "$out/config.after.json" 2>/dev/null || true
snapshot_hypr "$out/hypr.after.json"

summary_args=(
    --log "$out/harness.log"
    --known "$harness_src/known-env-warnings.txt"
    --config-before "$out/config.before.json"
    --config-after "$out/config.after.json"
    --hypr-before "$out/hypr.before.json"
    --hypr-after "$out/hypr.after.json"
    --out "$out/report.json"
    --exit-code "$status"
)
if ((strict)); then
    summary_args+=(--strict)
fi
if ((allow_writes)); then
    summary_args+=(--allow-config-writes)
fi
if ((hypr_stub)); then
    # With --strict, proves the stub was used and the Hyprland rows rendered available.
    summary_args+=(--hyprctl-log "$out/hyprctl.log")
fi
set +e
python3 "$script_dir/summarize.py" "${summary_args[@]}"
verdict=$?
set -e
printf 'renderer: %s\n' "$renderer"
if ((discard && verdict == 0)); then
    rm -rf -- "$out"
    printf 'output: discarded (passed)\n'
else
    printf 'output: %s\n' "$out"
fi
exit "$verdict"
