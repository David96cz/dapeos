#!/bin/bash
# shellcheck shell=bash
# Progress bar for the installer (writes to fd 3 = terminal).

PROGRESS_WIDTH=40

progress_init() {
    PROGRESS_PCT=0
    printf '\033[?25l' >&3
}

progress_show() {
    local pct="$1" label="$2"
    local filled=$((pct * PROGRESS_WIDTH / 100))
    local empty=$((PROGRESS_WIDTH - filled))
    local bar
    bar=$(printf '%*s' "$filled" '' | tr ' ' '#')
    bar+=$(printf '%*s' "$empty" '' | tr ' ' '-')
    printf '\r\033[2K[%s] %3d%%  %s' "$bar" "$pct" "$label" >&3
}

progress_done() {
    progress_show 100 "$1"
    printf '\n' >&3
    printf '\033[?25h' >&3
}

progress_fail() {
    printf '\n\033[1;31mFAILED: %s\033[0m\n' "$1" >&3
    printf 'See /var/log/dapeos-install.log\n' >&3
    printf '\033[?25h' >&3
}

run_phase() {
    local pct="$1" label="$2"
    shift 2
    progress_show "$pct" "$label"
    if ! "$@"; then
        progress_fail "$label"
        exit 1
    fi
}
