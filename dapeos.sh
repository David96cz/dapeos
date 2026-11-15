#!/bin/bash
# ==============================================================================
# DapeOS - instalační skript (vstupní bod)
# ==============================================================================
# Načte moduly a spustí instalaci. Veškerá logika je v lib/ a modules/.

BASE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CONTENTS_DIR="$BASE_DIR/contents"

# shellcheck source=lib/i18n.sh
source "$BASE_DIR/lib/i18n.sh"
# shellcheck source=lib/progress.sh
source "$BASE_DIR/lib/progress.sh"
# shellcheck source=lib/init.sh
source "$BASE_DIR/lib/init.sh"
# shellcheck source=lib/common.sh
source "$BASE_DIR/lib/common.sh"
# shellcheck source=lib/system.sh
source "$BASE_DIR/lib/system.sh"
# shellcheck source=lib/boot.sh
source "$BASE_DIR/lib/boot.sh"
# shellcheck source=lib/desktop.sh
source "$BASE_DIR/lib/desktop.sh"
# shellcheck source=modules/xfce/panel.sh
source "$BASE_DIR/modules/xfce/panel.sh"
# shellcheck source=modules/xfce/appearance.sh
source "$BASE_DIR/modules/xfce/appearance.sh"
# shellcheck source=modules/xfce/apps.sh
source "$BASE_DIR/modules/xfce/apps.sh"
# shellcheck source=modules/xfce/session.sh
source "$BASE_DIR/modules/xfce/session.sh"
# shellcheck source=modules/xfce/extras.sh
source "$BASE_DIR/modules/xfce/extras.sh"
# shellcheck source=modules/xfce/configure.sh
source "$BASE_DIR/modules/xfce/configure.sh"
# shellcheck source=modules/lxqt.sh
source "$BASE_DIR/modules/lxqt.sh"
# shellcheck source=modules/plasma.sh
source "$BASE_DIR/modules/plasma.sh"

choose_language() {
    local choice
    if [ -n "${DAPEOS_LANG:-}" ] && [ "$DAPEOS_LANG" != "en" ]; then
        return 0
    fi
    printf 'Select language / Vyberte jazyk:\n'
    printf '1) English\n'
    printf '2) Čeština\n'
    printf 'Choice / Volba [1]: '
    read -r choice </dev/tty || choice=1
    case "$choice" in
        2) DAPEOS_LANG="cs" ;;
        *) DAPEOS_LANG="en" ;;
    esac
    export DAPEOS_LANG
    export LANGUAGE="$DAPEOS_LANG"
}

main() {
    local no_reboot=false
    local lang_arg=""
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --no-reboot) no_reboot=true ;;
            --lang=*) lang_arg="${1#--lang=}" ;;
            -h|--help)
                echo "$(_ 'Usage: dapeos.sh [--no-reboot] [--lang=en|cs]')"
                exit 0
                ;;
            *) echo "$(_ 'Unknown parameter'): $1" >&2; exit 2 ;;
        esac
        shift
    done

    init_script

    clear_screen
    setup_banner
    if [ -n "$lang_arg" ]; then
        DAPEOS_LANG="$lang_arg"
        export DAPEOS_LANG
        export LANGUAGE="$DAPEOS_LANG"
    else
        choose_language
    fi
    clear_screen

    init_setup

    local LOG="/var/log/dapeos-install.log"
    mkdir -p /var/log
    touch "$LOG"
    if [ -w /dev/tty ]; then
        exec 3>/dev/tty
    else
        exec 3>&1
    fi
    exec >>"$LOG" 2>&1
    progress_init
    trap - ERR

    run_phase 5  "$(_ 'Preparing the system')" prepare_system
    run_phase 15 "$(_ 'Installing packages')" install_packages
    run_phase 45 "$(_ 'Configuring updates')" setup_auto_updates

    if [ "$DESKTOP_ENV" == "PLASMA" ]; then
        run_phase 55 "$(_ 'Configuring KDE Plasma')" configure_plasma
    elif [ "$DESKTOP_ENV" == "LXQT" ]; then
        run_phase 55 "$(_ 'Configuring LXQt')" configure_lxqt
    else
        run_phase 55 "$(_ 'Configuring XFCE')" configure_xfce
    fi

    run_phase 85 "$(_ 'Configuring display manager')" setup_display_manager
    run_phase 90 "$(_ 'Configuring boot')" setup_boot
    run_phase 95 "$(_ 'Applying security settings')" admin_security
    progress_done "$(_ 'Installation complete')"

    printf "\n==================================================\n" >&3
    printf "%s\n" "$(_ 'DONE')" >&3
    printf "==================================================\n" >&3
    if [ "$no_reboot" = "true" ]; then
        printf "%s\n" "$(_ 'Restart skipped (--no-reboot), repository kept.')" >&3
        exit 0
    fi

    if [ -f "$BASE_DIR/dapeos.sh" ]; then
        rm -rf "$BASE_DIR"
    fi

    printf "%s\n" "$(_ 'RESTARTING IN 5 SECONDS...')" >&3

    for i in {5..1}
    do
        printf "%s...\n" "$i" >&3
        sleep 1
    done
    printf "%s\n" "$(_ 'Restarting now!')" >&3
    reboot
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    if [ "$EUID" -eq 0 ]; then
        mkdir -p /var/log
        exec > >(tee -a /var/log/dapeos-install.log) 2>&1
    fi
    set -E
    trap 'die "Selhalo na řádku $LINENO (${BASH_SOURCE[0]})"' ERR
    main "$@"
fi
