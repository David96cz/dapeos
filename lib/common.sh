#!/bin/bash
# shellcheck shell=bash
# Společné utility: logování, chyby, práce s konfigurací.

log() {
    printf '\n\033[1;34m>> %s\033[0m\n' "$1"
}

warn() {
    printf '\n\033[1;33m>> %s\033[0m\n' "$1" >&2
}

die() {
    printf '\n\033[1;31mCHYBA: %s\033[0m\n' "$1" >&2
    exit 1
}

error() {
    die "$1"
}

debug() {
    [ "${DAPEOS_DEBUG:-0}" = "1" ] && printf '\033[2m[debug] %s\033[0m\n' "$1"
}


run_as_user() {
    su - "$REAL_USER" -c "dbus-launch $1" 2>/dev/null || true
}


get_setting() {
    local key="$1"
    if [ -f "$INSTALL_CONFIG" ]; then
        grep -i "^${key}=" "$INSTALL_CONFIG" | cut -d'=' -f2 | cut -d'#' -f1 | tr -d '[:space:]' || true
    fi
}


get_section() {
    local file="$1"
    local section="$2"
    if [ -f "$file" ]; then
        sed -n "/^\[$section\]/,/^\[/p" "$file" | grep -v '^\[.*\]' | grep -vE '^\s*(#|$)' | xargs || true
    fi
}

# === 1. PŘÍPRAVA A INTERAKTIVNÍ DOTAZY ===


config_lines() {
    local file="$1" section="$2"
    [ -f "$file" ] || return 0
    awk -v s="[$section]" '
        $0 == s { f=1; next }
        /^\[/    { f=0 }
        f && $0 !~ /^[[:space:]]*(#|$)/ { print }
    ' "$file" | tr -d '\r'
}
