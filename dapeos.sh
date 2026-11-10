#!/bin/bash
# ==============================================================================
# DapeOS - instalační skript (vstupní bod)
# ==============================================================================
# Načte moduly a spustí instalaci. Veškerá logika je v lib/ a modules/.

BASE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CONTENTS_DIR="$BASE_DIR/contents"

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

main() {
    local no_reboot=false
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --no-reboot) no_reboot=true ;;
            -h|--help)
                echo "Použití: $0 [--no-reboot]"
                exit 0
                ;;
            *) echo "Neznámý parametr: $1" >&2; exit 2 ;;
        esac
        shift
    done

    init_script
    init_setup
    prepare_system
    install_packages
    setup_auto_updates

    if [ "$DESKTOP_ENV" == "PLASMA" ]; then
        configure_plasma
    elif [ "$DESKTOP_ENV" == "LXQT" ]; then
        configure_lxqt
    else
        configure_xfce
    fi

    setup_display_manager
    setup_boot
    admin_security
    echo "=================================================="
    echo "HOTOVO"
    echo "=================================================="
    if [ "$no_reboot" = "true" ]; then
        echo "Restart přeskočen (--no-reboot), repo ponecháno."
        exit 0
    fi

    if [ -f "$BASE_DIR/dapeos.sh" ]; then
        rm -rf "$BASE_DIR"
    fi

    echo "RESTART ZA 5 SEKUND..."

    for i in {5..1}
    do
        echo "$i..."
        sleep 1
    done
    echo "Restartuji nyní!"
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
