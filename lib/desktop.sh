#!/bin/bash
# shellcheck shell=bash
# Práce s .desktop soubory na jednom místě.

desktop_set_key() {
    local file="$1" key="$2" value="$3" esc
    [ -f "$file" ] || return 1
    esc=$(printf '%s' "$value" | sed -e 's/[&|\\]/\\&/g')
    if grep -q "^${key}=" "$file"; then
        sed -i "s|^${key}=.*|${key}=${esc}|" "$file"
    else
        sed -i "/^\[Desktop Entry\]/a ${key}=${value}" "$file"
    fi
}

desktop_ensure_key() {
    local file="$1" key="$2" value="$3"
    grep -q "^${key}=" "$file" || desktop_set_key "$file" "$key" "$value"
}

desktop_remove_key() {
    local file="$1" key="$2"
    [ -f "$file" ] || return 1
    sed -i "/^${key}=/d" "$file"
}

desktop_hide() {
    local file="$1"
    [ -f "$file" ] || return 1
    desktop_remove_key "$file" Hidden
    desktop_remove_key "$file" NoDisplay
    desktop_ensure_key "$file" NoDisplay true
}

desktop_add_category() {
    local file="$1"; shift
    [ -f "$file" ] || return 1
    local cur cat
    cur=$(sed -n 's/^Categories=//p' "$file" | head -1)
    cur="${cur%;}"
    for cat in "$@"; do
        case ";$cur;" in
            *";$cat;"*) ;;
            *) cur="${cur:+$cur;}$cat" ;;
        esac
    done
    desktop_set_key "$file" Categories "${cur};"
}

autostart_sync() {
    local config="$1"
    local dir="$USER_HOME/.config/autostart"
    local line cmd base raw name file
    mkdir -p "$dir"

    while IFS= read -r line; do
        [ -n "$line" ] || continue
        cmd="$line"
        base="$(basename "${cmd%% *}")"
        raw="${base%.*}"
        name="$(printf '%s' "${raw:0:1}" | tr '[:lower:]' '[:upper:]')${raw:1}"
        file="$dir/${raw}.desktop"

        {
            printf '[Desktop Entry]\n'
            printf 'Type=Application\n'
            printf 'Name=%s\n' "$name"
            printf 'Exec=%s\n' "$cmd"
            printf 'Terminal=false\n'
            printf 'Hidden=false\n'
        } > "$file"

        log "Autostart: $raw (Exec: $cmd)"
    done < <(config_lines "$config" AUTORUN)

    chown -R "$REAL_USER:$REAL_USER" "$dir" 2>/dev/null || true
}
