#!/bin/bash
# shellcheck shell=bash
# Progress bar for the installer (writes to fd 3 = terminal).

PROGRESS_WIDTH=40
SPINNER_PID=""

progress_render() {
    local pct="$1" label="$2" spin="$3" elapsed="$4"
    local filled=$((pct * PROGRESS_WIDTH / 100))
    local empty=$((PROGRESS_WIDTH - filled))
    local bar
    bar=$(printf '%*s' "$filled" '' | tr ' ' '#')
    bar+=$(printf '%*s' "$empty" '' | tr ' ' '-')
    if [ -n "$spin" ]; then
        printf '\r\033[2K[%s] %s %3d%%  %s  %ss' "$bar" "$spin" "$pct" "$label" "$elapsed" >&3
    else
        printf '\r\033[2K[%s] %3d%%  %s' "$bar" "$pct" "$label" >&3
    fi
}

progress_init() {
    PROGRESS_PCT=0
    printf '\033[?25l' >&3
}

progress_show() {
    progress_render "$1" "$2" "" ""
}

progress_spinner_start() {
    local pct="$1" label="$2" start=$SECONDS
    local chars='|/-\\'
    (
        local i=0
        while :; do
            progress_render "$pct" "$label" "${chars:i:1}" "$((SECONDS - start))"
            i=$(((i + 1) % 4))
            sleep 0.15
        done
    ) &
    SPINNER_PID=$!
}

progress_spinner_stop() {
    if [ -n "$SPINNER_PID" ]; then
        kill "$SPINNER_PID" 2>/dev/null || true
        wait "$SPINNER_PID" 2>/dev/null || true
        SPINNER_PID=""
    fi
}

progress_done() {
    progress_render 100 "$1" "" ""
    printf '\n' >&3
    printf '\033[?25h' >&3
}

progress_fail() {
    progress_spinner_stop
    printf '\n\033[1;31mFAILED: %s\033[0m\n' "$1" >&3
    printf 'See /var/log/dapeos-install.log\n' >&3
    printf '\033[?25h' >&3
}

run_phase() {
    local pct="$1" label="$2"
    shift 2
    progress_spinner_start "$pct" "$label"
    if ! "$@"; then
        progress_spinner_stop
        progress_fail "$label"
        exit 1
    fi
    progress_spinner_stop
    progress_show "$pct" "$label"
}
