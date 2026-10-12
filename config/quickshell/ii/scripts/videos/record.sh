#!/usr/bin/env bash
set -euo pipefail

CONFIG_FILE="$HOME/.config/illogical-impulse/config.json"
RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}/illogical-impulse"
PID_FILE="$RUNTIME_DIR/wf-recorder.pid"
PAUSE_FILE="$RUNTIME_DIR/wf-recorder.paused"
COMBINE_PIDS="$RUNTIME_DIR/combine-pids.txt"

read_config() {
    local jq_path="$1"
    local fallback="$2"
    local value=""
    value="$(jq -r "${jq_path} // empty" "$CONFIG_FILE" 2>/dev/null || true)"
    if [[ -n "$value" && "$value" != "null" ]]; then
        printf '%s\n' "$value"
    else
        printf '%s\n' "$fallback"
    fi
}

RECORDING_DIR="$(read_config '.screenRecord.savePath' "$HOME/Videos")"
FILE_FORMAT="$(read_config '.screenRecord.fileFormat' 'mp4')"
FPS="$(read_config '.screenRecord.fps' '60')"
PIXEL_FORMAT="$(read_config '.screenRecord.pixelFormat' 'yuv420p')"
FULLSCREEN_FOCUSED_MONITOR="$(read_config '.screenRecord.fullscreenUsesFocusedMonitor' 'true')"
AUDIO_SOURCE="$(read_config '.screenRecord.audioSource' 'system')"

# Clean up stale combine-pids from previous crashed sessions
if [[ -f "$COMBINE_PIDS" ]]; then
    if ! tracked_pid > /dev/null 2>&1; then
        cleanup_combined_audio
    fi
fi

case "$AUDIO_SOURCE" in
    system|mic|none|both) ;;
    *) AUDIO_SOURCE="system" ;;
esac

case "$FILE_FORMAT" in
    mp4|mkv|webm) ;;
    *) FILE_FORMAT="mp4" ;;
esac

if ! [[ "$FPS" =~ ^[0-9]+$ ]] || (( FPS < 1 || FPS > 240 )); then
    FPS=60
fi

case "$PIXEL_FORMAT" in
    yuv420p|nv12|auto) ;;
    *) PIXEL_FORMAT="yuv420p" ;;
esac

getdate() {
    date '+%Y-%m-%d_%H.%M.%S'
}
get_system_audio() {
    local dev
    dev="$(read_config '.screenRecord.systemAudioDevice' '')"
    if [[ -z "$dev" ]]; then
        printf '%s.monitor\n' "$(pactl get-default-sink)"
    else
        printf '%s.monitor\n' "$dev"
    fi
}
get_mic_audio() {
    local dev
    dev="$(read_config '.screenRecord.micDevice' '')"
    if [[ -z "$dev" ]]; then
        pactl get-default-source
    else
        printf '%s\n' "$dev"
    fi
}
create_combined_audio() {
    command -v pactl >/dev/null || { notify-send "Recording error" "pactl is required for combined audio" -a "Recorder" & disown; return 1; }
    local sink_name="recording_mix_$$"
    local sink_mod sys_mod mic_mod
    sink_mod="$(pactl load-module module-null-sink sink_name="$sink_name")"
    sys_mod="$(pactl load-module module-loopback source="$(get_system_audio)" sink="$sink_name")"
    mic_mod="$(pactl load-module module-loopback source="$(get_mic_audio)" sink="$sink_name")"
    printf '%s\n' "$sink_mod" > "$COMBINE_PIDS"
    printf '%s\n' "$sys_mod" >> "$COMBINE_PIDS"
    printf '%s\n' "$mic_mod" >> "$COMBINE_PIDS"
    printf '%s' "$sink_name"
}
cleanup_combined_audio() {
    if [[ -f "$COMBINE_PIDS" ]]; then
        while IFS= read -r mod; do
            pactl unload-module "$mod" 2>/dev/null || true
        done < "$COMBINE_PIDS"
        rm -f "$COMBINE_PIDS"
    fi
}
get_audio_device() {
    local source_type="${1:-$AUDIO_SOURCE}"
    case "$source_type" in
        mic) get_mic_audio ;;
        system) get_system_audio ;;
        both)
            mkdir -p "$RUNTIME_DIR"
            printf '%s.monitor\n' "$(create_combined_audio)"
            ;;
        none|*) return 1 ;;
    esac
}
getactivemonitor() {
    hyprctl monitors -j | jq -r '.[] | select(.focused == true) | .name'
}

tracked_pid() {
    if [[ -f "$PID_FILE" ]]; then
        local pid
        pid="$(<"$PID_FILE")"
        if [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; then
            printf '%s\n' "$pid"
            return 0
        fi
    fi
    return 1
}

stop_recording() {
    local pid=""
    if pid="$(tracked_pid)"; then
        notify-send "Recording Stopped" "Stopped" -a 'Recorder' & disown
        kill "$pid" 2>/dev/null || true
        rm -f "$PID_FILE" "$PAUSE_FILE"
        cleanup_combined_audio
        return 0
    fi
    cleanup_combined_audio
    notify-send "No active recording" "Nothing to stop" -a 'Recorder' & disown
}

pause_recording() {
    local pid=""
    if ! pid="$(tracked_pid)"; then
        notify-send "No active recording" "Nothing to pause" -a 'Recorder' & disown
        return 1
    fi
    if [[ -f "$PAUSE_FILE" ]]; then
        kill -CONT "$pid" 2>/dev/null || true
        rm -f "$PAUSE_FILE"
        notify-send "Recording resumed" "Resumed" -a 'Recorder' & disown
    else
        kill -STOP "$pid" 2>/dev/null || true
        : > "$PAUSE_FILE"
        notify-send "Recording paused" "Paused" -a 'Recorder' & disown
    fi
}

run_recorder() {
    mkdir -p "$RUNTIME_DIR"
    "${wf_args[@]}" &
    local recorder_pid=$!
    printf '%s\n' "$recorder_pid" > "$PID_FILE"
    rm -f "$PAUSE_FILE"
    set +e
    wait "$recorder_pid"
    local status=$?
    set -e
    rm -f "$PID_FILE" "$PAUSE_FILE"
    cleanup_combined_audio
    exit "$status"
}

resolve_audio_args() {
    # Returns audio flags based on explicit flags and AUDIO_SOURCE config.
    # Priority: --sound > --mic > AUDIO_SOURCE config
    local use_system=0
    local use_mic=0

    if [[ $SOUND_FLAG -eq 1 && $MIC_FLAG -eq 1 ]]; then
        use_system=1
        use_mic=1
    elif [[ $SOUND_FLAG -eq 1 ]]; then
        use_system=1
    elif [[ $MIC_FLAG -eq 1 ]]; then
        use_mic=1
    else
        # Fall back to config
        case "$AUDIO_SOURCE" in
            system) use_system=1 ;;
            mic) use_mic=1 ;;
            both) use_system=1; use_mic=1 ;;
            none) ;;
        esac
    fi

    local audio_args=()
    local audio_dev=""
    if [[ $use_system -eq 1 && $use_mic -eq 1 ]]; then
        audio_dev="$(get_audio_device both || true)"
    elif [[ $use_system -eq 1 ]]; then
        audio_dev="$(get_audio_device system || true)"
    elif [[ $use_mic -eq 1 ]]; then
        audio_dev="$(get_audio_device mic || true)"
    fi
    if [[ -n "$audio_dev" ]]; then
        audio_args+=(--audio="$audio_dev")
    fi
    if [[ ${#audio_args[@]} -gt 0 ]]; then
        printf '%s\0' "${audio_args[@]}"
    fi
}

build_wf_args() {
    local output_file="$1"
    shift
    local args=("wf-recorder" "-f" "$output_file" "-t" "--framerate" "$FPS")
    if [[ "$PIXEL_FORMAT" != "auto" ]]; then
        args+=("--pixel-format" "$PIXEL_FORMAT")
    fi
    # Resolve audio args and append
    mapfile -d '' audio_extra < <(resolve_audio_args)
    args+=("${audio_extra[@]}")
    args+=("$@")
    printf '%s\0' "${args[@]}"
}

# parse --region <value> without modifying $@ so other flags like --fullscreen still work
ARGS=("$@")
MANUAL_REGION=""
SOUND_FLAG=0
MIC_FLAG=0
FULLSCREEN_FLAG=0
STOP_FLAG=0
PAUSE_FLAG=0
for ((i=0;i<${#ARGS[@]};i++)); do
    if [[ "${ARGS[i]}" == "--region" ]]; then
        if (( i+1 < ${#ARGS[@]} )); then
            MANUAL_REGION="${ARGS[i+1]}"
        else
            notify-send "Recording cancelled" "No region specified for --region" -a 'Recorder' & disown
            exit 1
        fi
    elif [[ "${ARGS[i]}" == "--sound" ]]; then
        SOUND_FLAG=1
    elif [[ "${ARGS[i]}" == "--mic" ]]; then
        MIC_FLAG=1
    elif [[ "${ARGS[i]}" == "--fullscreen" ]]; then
        FULLSCREEN_FLAG=1
    elif [[ "${ARGS[i]}" == "--stop" ]]; then
        STOP_FLAG=1
    elif [[ "${ARGS[i]}" == "--pause" ]]; then
        PAUSE_FLAG=1
    elif [[ "${ARGS[i]}" == "--no-audio" ]]; then
        AUDIO_SOURCE="none"
    fi
done

if [[ $STOP_FLAG -eq 1 ]]; then
    stop_recording
    exit 0
fi

if [[ $PAUSE_FLAG -eq 1 ]]; then
    pause_recording
    exit 0
fi

mkdir -p "$RECORDING_DIR"
cd "$RECORDING_DIR" || exit

if tracked_pid > /dev/null; then
    stop_recording
else
    output_file="./recording_$(getdate).${FILE_FORMAT}"
    if [[ $FULLSCREEN_FLAG -eq 1 ]]; then
        notify-send "Starting recording" "${output_file#./}" -a 'Recorder' & disown
        output_args=()
        if [[ "$FULLSCREEN_FOCUSED_MONITOR" == "true" ]]; then
            output_args+=("-o" "$(getactivemonitor)")
        fi
        mapfile -d '' wf_args < <(build_wf_args "$output_file" "${output_args[@]}")
        run_recorder
    else
        # If a manual region was provided via --region, use it; otherwise run slurp as before.
        if [[ -n "$MANUAL_REGION" ]]; then
            region="$MANUAL_REGION"
        else
            if ! region="$(slurp 2>&1)"; then
                notify-send "Recording cancelled" "Selection was cancelled" -a 'Recorder' & disown
                exit 1
            fi
        fi

        notify-send "Starting recording" "${output_file#./}" -a 'Recorder' & disown
        mapfile -d '' wf_args < <(build_wf_args "$output_file" --geometry "$region")
        run_recorder
    fi
fi
