#!/bin/bash
# shellcheck shell=bash
# Installer gettext helpers.
: "${DAPEOS_LANG:=en}"
export DAPEOS_LANG
export TEXTDOMAIN="${TEXTDOMAIN:-dapeos-installer}"
export TEXTDOMAINDIR="${BASE_DIR:-.}/locale"

if command -v gettext >/dev/null 2>&1; then
    _() { gettext "$1"; }
else
    _() { printf '%s' "$1"; }
fi

clear_screen() {
    printf "\033[2J\033[3J\033[H"
}
