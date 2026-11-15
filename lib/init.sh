#!/bin/bash
# shellcheck shell=bash
# Inicializace: globální proměnné a interaktivní setup.

init_script() {
    set -e # Ukončí skript při první vážné chybě

    # === GLOBÁLNÍ PROMĚNNÉ A CESTY ===
    BASE_DIR="$(dirname "$(realpath "$0")")"
    CONTENTS_DIR="$BASE_DIR/contents"
    INSTALL_CONFIG="$CONTENTS_DIR/install.conf"

    # Bezpečnější detekce původního uživatele (hledá UID 1000+)
    REAL_USER=$(getent passwd | awk -F: '$3 >= 1000 && $3 < 60000 {print $1}' | head -n 1)
    if [ -z "$REAL_USER" ]; then
        echo -e "\033[1;31mCHYBA: Nepodařilo se najít žádného běžného uživatele (UID 1000+).\033[0m" >&2
        exit 1
    fi
    # Přesná detekce home složky podle databáze uživatelů
    USER_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)

    # Detekce jazyka
    SYS_LOCALE=$(grep "^LANG=" /etc/default/locale | cut -d'=' -f2 | tr -d '"' || echo "en_US.UTF-8")
    SYS_LANG_CODE="${SYS_LOCALE%%.*}"

    # Přidána detekce architektury (amd64 nebo arm64)
    SYS_ARCH=$(dpkg --print-architecture)
}


setup_banner() {
    echo -e "\033[1;36m==================================================\033[0m"
    echo -e "\033[1;36m                 DapeOS SETUP                     \033[0m"
    echo -e "\033[1;36m==================================================\033[0m"
    echo -e " \033[1;33m$(_ '(Type R at any time to reset and return to the beginning)')\033[0m"
    echo -e "\033[1;36m--------------------------------------------------\033[0m"
    echo ""
}

init_setup() {
    [ "$EUID" -ne 0 ] && error "$(_ 'Must be run as root (sudo)')"
    
    log "$(_ 'Detected system installation language:')"
    log "$(_ 'Installation will be performed for user:')"
    sleep 1

    # Detekce stavu hesla ROOT
    ROOT_HASH=$(awk -F: '$1=="root" {print $2}' /etc/shadow)
    if [[ "$ROOT_HASH" == "*" || "$ROOT_HASH" == "!" ]]; then
        ROOT_LOCKED="TRUE" # Uživatel nechal heslo roota při instalaci prázdné
    else
        ROOT_LOCKED="FALSE" # Uživatel heslo roota nastavil
    fi

    # HLAVNÍ INTERAKTIVNÍ SMYČKA
    while true; do
        clear
        setup_banner

        echo "1. Choose desktop environment"
        while true; do
            echo "1) KDE Plasma"
            echo "2) LXQT"
            echo "3) XFCE"
            read -p "$(_ 'Enter number: ')" DISTRO_ANS
            case "$DISTRO_ANS" in
                1) DESKTOP_ENV="PLASMA"; DESKTOP_STR="KDE Plasma"; break ;;
                2) DESKTOP_ENV="LXQT"; DESKTOP_STR="LXQt"; break ;;
                3) DESKTOP_ENV="XFCE"; DESKTOP_STR="XFCE"; break ;;
                r|R) continue 2 ;;
                *) echo -e "\033[1;31mNeplatná volba! Zadej 1, 2, 3 nebo R.\033[0m" ;;
            esac
        done


        echo "--------------------------------------------------"
        echo "2. Choose browser"
        while true; do
            echo "1) Chrome"
            echo "2) Chromium"
            echo "3) Brave"
            echo "4) Firefox"
            echo "5) Nic"
            read -p "$(_ 'Enter number (1-5): ')" BROWSER_CHOICE
            case "$BROWSER_CHOICE" in
                1) BROWSER_STR="Google Chrome"; break ;;
                2) BROWSER_STR="Chromium"; break ;;
                3) BROWSER_STR="Brave"; break ;;
                4) BROWSER_STR="Firefox"; break ;;
                5) BROWSER_STR="Žádný"; break ;;
                r|R) continue 2 ;;
                *) echo -e "\033[1;31mNeplatná volba! Zadej číslo 1 až 5 nebo R.\033[0m" ;;
            esac
        done

        echo "--------------------------------------------------"
        echo "3. Choose office suite"
        while true; do
            echo "1) LibreOffice"
            echo "2) OnlyOffice"
            echo "3) Nic"
            read -p "$(_ 'Enter number (1-3): ')" OFFICE_CHOICE
            case "$OFFICE_CHOICE" in
                1) OFFICE_STR="LibreOffice"; break ;;
                2) OFFICE_STR="OnlyOffice"; break ;;
                3) OFFICE_STR="Žádný"; break ;;
                r|R) continue 2 ;;
                *) echo -e "\033[1;31mNeplatná volba! Zadej číslo 1 až 3 nebo R.\033[0m" ;;
            esac
        done

        echo "--------------------------------------------------"
        echo "4. Enable automatic login?"
        while true; do
            echo "1) Ano"
            echo "2) Ne"
            read -p "$(_ 'Enter number (1 or 2): ')" AUTO_ANS
            case "$AUTO_ANS" in
                1) AUTOLOGIN_REQ="TRUE"; AUTOLOGIN_STR="Ano"; break ;;
                2) AUTOLOGIN_REQ="FALSE"; AUTOLOGIN_STR="Ne"; break ;;
                r|R) continue 2 ;;
                *) echo -e "\033[1;31mNeplatná volba! Zadej 1, 2 nebo R.\033[0m" ;;
            esac
        done

        echo "--------------------------------------------------"
        echo "5. Choose computer security profile (passwords and permissions)"
        echo ""
        
        # Možnost 1 a 2 jsou dostupné vždy
        echo "1) Family PC / Windows style (NO PASSWORD)"
        echo "   - The computer boots straight to the desktop."
        echo "   - Sudo and app installation run silently or with a click (no password)."
        echo "2) Personal PC (STANDARD LINUX)"
        echo "   - Requires the user password for login and sudo/installations."
        
        # Možnost 3 je dostupná JEN pokud si uživatel nastavil heslo roota při instalaci
        if [ "$ROOT_LOCKED" == "FALSE" ]; then
            echo "3) Strict Administrator (SEPARATE PRIVILEGES)"
            echo "   - The user has their own password (or none) for login."
            echo "   - Installing apps and system changes always require the ROOT password."
        else
            echo -e "\033[1;30m3) Přísný Administrátor - NEDOSTUPNÉ (Při instalaci Debianu nebylo nastaveno heslo ROOTa)\033[0m"
        fi

        while true; do
            read -p "$(_ 'Enter profile number (1, 2 or 3): ')" SEC_ANS
            case "$SEC_ANS" in
                1)
                    SEC_PROFILE="FAMILY"
                    SEC_STR="Rodinný PC (Bez hesel)"
                    break
                    ;;
                2)
                    SEC_PROFILE="STANDARD"
                    SEC_STR="Standardní Linux (Uživatelské heslo)"
                    break
                    ;;
                3)
                    if [ "$ROOT_LOCKED" == "FALSE" ]; then
                        SEC_PROFILE="ADMIN"
                        SEC_STR="Přísný Administrátor (Vyžaduje ROOT heslo)"
                        break
                    else
                        echo -e "\033[1;31mTato volba vyžaduje nastavené heslo ROOTa.\033[0m"
                    fi
                    ;;
                r|R) continue 2 ;;
                *) echo -e "\033[1;31mNeplatná volba!\033[0m" ;;
            esac
        done

        # Zeptáme se na smazání hesla JEN pokud je sudo kryté rootem
        if [ "$ROOT_ADMIN_ONLY" == "TRUE" ]; then
            echo "--------------------------------------------------"
            echo "5b. Remove the user login password? (Windows style - login with a click. Safe, sudo is protected by the ROOT password.)"
            while true; do
                echo "1) Yes (remove the regular user password)"
                echo "2) No (keep the user password)"
                read -p "$(_ 'Enter number (1 or 2): ')" PASS_ANS
                case "$PASS_ANS" in
                    1) REMOVE_PASS="TRUE"; REMOVE_PASS_STR="Ano (Bez hesla)"; break ;;
                    2) REMOVE_PASS="FALSE"; REMOVE_PASS_STR="Ne (S heslem)"; break ;;
                    r|R) continue 2 ;;
                    *) echo -e "\033[1;31mNeplatná volba! Zadej 1, 2 nebo R.\033[0m" ;;
                esac
            done
        fi

        echo "--------------------------------------------------"
        echo "6. Install Wine and Winetricks for Windows applications?"
        while true; do
            echo "1) Ano"
            echo "2) Ne"
            read -p "$(_ 'Enter number (1 or 2): ')" WINE_ANS
            case "$WINE_ANS" in
                1) WINE_REQ="TRUE"; WINE_STR="Ano"; break ;;
                2) WINE_REQ="FALSE"; WINE_STR="Ne"; break ;;
                r|R) continue 2 ;;
                *) echo -e "\033[1;31mNeplatná volba! Zadej 1, 2 nebo R.\033[0m" ;;
            esac
        done

        echo "--------------------------------------------------"
        echo "7. Install RustDesk (Remote Desktop)?"
        echo "   Lets you control this computer from another device, or vice versa."
        echo "   Ideal for quick technical support or remote management."
        while true; do
            echo "1) Yes (install RustDesk)"
            echo "2) No (skip)"
            read -p "$(_ 'Enter number (1 or 2): ')" RUSTDESK_ANS
            case "$RUSTDESK_ANS" in
                1) RUSTDESK_REQ="TRUE"; RUSTDESK_STR="Ano"; break ;;
                2) RUSTDESK_REQ="FALSE"; RUSTDESK_STR="Ne"; break ;;
                r|R) continue 2 ;;
                *) echo -e "\033[1;31mNeplatná volba! Zadej 1, 2 nebo R.\033[0m" ;;
            esac
        done

        # SOUHRN A POTVRZENÍ
        clear
        echo -e "\033[1;36m==================================================\033[0m"
        echo -e "\033[1;36m                 SOUHRN NASTAVENÍ                 \033[0m"
        echo -e "\033[1;36m==================================================\033[0m"
        echo " Cílový uživatel:  $REAL_USER"
        echo " Prostředí:        $DESKTOP_STR"
        echo " Prohlížeč:        $BROWSER_STR"
        echo " Office:           $OFFICE_STR"
        echo " Bezpečnost:       $SEC_STR"
        echo " Wine podpora:     $WINE_STR"
        echo " RustDesk:         $RUSTDESK_STR"
        echo -e "\033[1;36m==================================================\033[0m"
        echo "Is this configuration correct?"
        while true; do
            echo "1) Yes (start installation)"
            echo "2) No (start over)"
            read -p "$(_ 'Enter number (1 or 2, or R to restart): ')" CONFIRM_ANS
            case "$CONFIRM_ANS" in
                1) break 2 ;; 
                2|r|R) continue 2 ;; 
                *) echo -e "\033[1;31mNeplatná volba! Zadej 1, 2 nebo R.\033[0m" ;;
            esac
        done
    done

    # Definice lokálního konfiguráku
    local _de
    _de="$(echo "$DESKTOP_ENV" | tr '[:upper:]' '[:lower:]')"
    DESKTOP_CONFIG="$CONTENTS_DIR/$_de/$_de.conf"

    # Načtení zbytku globálních nastavení
    TIMEOUT=$(get_setting "GRUB_TIMEOUT")
    TIMEOUT=${TIMEOUT:-0}
    
    CONF_OUT_RAW=$(get_setting "CONFIRM_LOGOUT" | tr '[:lower:]' '[:upper:]')
    [[ "$CONF_OUT_RAW" == "TRUE" ]] && CONF_OUT="true" || CONF_OUT="false"
    
    BOOT_LOGO=$(get_setting "BOOT_LOGO" | tr '[:lower:]' '[:upper:]')
}

# === POMOCNÉ FUNKCE ===

