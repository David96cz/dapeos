#!/bin/bash
# shellcheck shell=bash
# Inicializace: globální proměnné a interaktivní setup.

init_script() {
    set -e # Ukončí skript při první vážné chybě

    # === GLOBÁLNÍ PROMĚNNÉ A CESTY ===
    BASE_DIR="$(dirname "$(realpath "$0")")"
    CONTENTS_DIR="$BASE_DIR/contents"
    GLOBAL_CONFIG="$CONTENTS_DIR/setup-config.txt"

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


init_setup() {
    [ "$EUID" -ne 0 ] && error "Nutno spustit jako root (sudo)"
    
    log "Detekován systémový jazyk instalace: $SYS_LANG_CODE"
    log "Instalace bude provedena pro uživatele: $REAL_USER"
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
        echo -e "\033[1;36m==================================================\033[0m"
        echo -e "\033[1;36m                 DapeOS SETUP                     \033[0m"
        echo -e "\033[1;36m==================================================\033[0m"
        echo -e " \033[1;33m(Kdykoliv zadej 'R' pro reset a návrat na začátek)\033[0m"
        echo -e "\033[1;36m--------------------------------------------------\033[0m"
        echo ""

        echo "1. Vyber desktopové prostředí"
        while true; do
            echo "1) KDE Plasma"
            echo "2) LXQT"
            echo "3) XFCE"
            read -p "Zadej číslo: " DISTRO_ANS
            case "$DISTRO_ANS" in
                1) DESKTOP_ENV="PLASMA"; DESKTOP_STR="KDE Plasma"; break ;;
                2) DESKTOP_ENV="LXQT"; DESKTOP_STR="LXQt"; break ;;
                3) DESKTOP_ENV="XFCE"; DESKTOP_STR="XFCE"; break ;;
                r|R) continue 2 ;;
                *) echo -e "\033[1;31mNeplatná volba! Zadej 1, 2, 3 nebo R.\033[0m" ;;
            esac
        done


        echo "--------------------------------------------------"
        echo "2. Vyber prohlížeč"
        while true; do
            echo "1) Chrome"
            echo "2) Chromium"
            echo "3) Brave"
            echo "4) Firefox"
            echo "5) Nic"
            read -p "Zadej číslo (1 až 5): " BROWSER_CHOICE
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
        echo "3. Vyber kancelářský balík"
        while true; do
            echo "1) LibreOffice"
            echo "2) OnlyOffice"
            echo "3) Nic"
            read -p "Zadej číslo (1 až 3): " OFFICE_CHOICE
            case "$OFFICE_CHOICE" in
                1) OFFICE_STR="LibreOffice"; break ;;
                2) OFFICE_STR="OnlyOffice"; break ;;
                3) OFFICE_STR="Žádný"; break ;;
                r|R) continue 2 ;;
                *) echo -e "\033[1;31mNeplatná volba! Zadej číslo 1 až 3 nebo R.\033[0m" ;;
            esac
        done

        echo "--------------------------------------------------"
        echo "4. Chceš nastavit automatické přihlašování?"
        while true; do
            echo "1) Ano"
            echo "2) Ne"
            read -p "Zadej číslo (1 nebo 2): " AUTO_ANS
            case "$AUTO_ANS" in
                1) AUTOLOGIN_REQ="TRUE"; AUTOLOGIN_STR="Ano"; break ;;
                2) AUTOLOGIN_REQ="FALSE"; AUTOLOGIN_STR="Ne"; break ;;
                r|R) continue 2 ;;
                *) echo -e "\033[1;31mNeplatná volba! Zadej 1, 2 nebo R.\033[0m" ;;
            esac
        done

        echo "--------------------------------------------------"
        echo "5. Zvolte bezpečnostní profil počítače (Správa hesel a oprávnění)"
        echo ""
        
        # Možnost 1 a 2 jsou dostupné vždy
        echo "1) Rodinný PC / Windows styl (BEZ HESLA)"
        echo "   - Počítač startuje rovnou na plochu."
        echo "   - Sudo a instalace programů se provádí tiše nebo jen kliknutím (bez zadávání hesla)."
        echo "2) Osobní PC (STANDARDNÍ LINUX)"
        echo "   - Vyžaduje heslo uživatele pro přihlášení i pro sudo/instalace."
        
        # Možnost 3 je dostupná JEN pokud si uživatel nastavil heslo roota při instalaci
        if [ "$ROOT_LOCKED" == "FALSE" ]; then
            echo "3) Přísný Administrátor (ODDĚLENÁ PRÁVA)"
            echo "   - Uživatel má své heslo (nebo žádné) pro přihlášení."
            echo "   - Pro instalaci programů a zásahy do systému je vždy nutné zadat heslo ROOTa."
        else
            echo -e "\033[1;30m3) Přísný Administrátor - NEDOSTUPNÉ (Při instalaci Debianu nebylo nastaveno heslo ROOTa)\033[0m"
        fi

        while true; do
            read -p "Zadej číslo profilu (1, 2 nebo 3): " SEC_ANS
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
            echo "5b. Odstranit uživateli heslo pro přihlášení? (Windows styl - přihlášení jen kliknutím. Bezpečné, protože sudo už je chráněno ROOT heslem.)"
            while true; do
                echo "1) Ano (Vymazat heslo běžného uživatele)"
                echo "2) Ne (Ponechat uživateli heslo)"
                read -p "Zadej číslo (1 nebo 2): " PASS_ANS
                case "$PASS_ANS" in
                    1) REMOVE_PASS="TRUE"; REMOVE_PASS_STR="Ano (Bez hesla)"; break ;;
                    2) REMOVE_PASS="FALSE"; REMOVE_PASS_STR="Ne (S heslem)"; break ;;
                    r|R) continue 2 ;;
                    *) echo -e "\033[1;31mNeplatná volba! Zadej 1, 2 nebo R.\033[0m" ;;
                esac
            done
        fi

        echo "--------------------------------------------------"
        echo "6. Chceš nainstalovat Wine a Winetricks pro Windows aplikace?"
        while true; do
            echo "1) Ano"
            echo "2) Ne"
            read -p "Zadej číslo (1 nebo 2): " WINE_ANS
            case "$WINE_ANS" in
                1) WINE_REQ="TRUE"; WINE_STR="Ano"; break ;;
                2) WINE_REQ="FALSE"; WINE_STR="Ne"; break ;;
                r|R) continue 2 ;;
                *) echo -e "\033[1;31mNeplatná volba! Zadej 1, 2 nebo R.\033[0m" ;;
            esac
        done

        echo "--------------------------------------------------"
        echo "7. Instalace RustDesk (Vzdálená plocha)?"
        echo "   Umožňuje ovládat tento počítač z jiného zařízení nebo naopak."
        echo "   Ideální pro rychlou technickou pomoc nebo správu na dálku."
        while true; do
            echo "1) Ano (Nainstalovat RustDesk)"
            echo "2) Ne (Přeskočit)"
            read -p "Zadej číslo (1 nebo 2): " RUSTDESK_ANS
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
        echo "Je toto nastavení správné?"
        while true; do
            echo "1) Ano (Spustit instalaci)"
            echo "2) Ne (Začít znovu)"
            read -p "Zadej číslo (1 nebo 2, případně R pro restart): " CONFIRM_ANS
            case "$CONFIRM_ANS" in
                1) break 2 ;; 
                2|r|R) continue 2 ;; 
                *) echo -e "\033[1;31mNeplatná volba! Zadej 1, 2 nebo R.\033[0m" ;;
            esac
        done
    done

    # Definice lokálního konfiguráku
    LOCAL_CONFIG="$CONTENTS_DIR/$(echo "$DESKTOP_ENV" | tr '[:upper:]' '[:lower:]')/config.txt"

    # Načtení zbytku globálních nastavení
    TIMEOUT=$(get_setting "GRUB_TIMEOUT")
    TIMEOUT=${TIMEOUT:-0}
    
    CONF_OUT_RAW=$(get_setting "CONFIRM_LOGOUT" | tr '[:lower:]' '[:upper:]')
    [[ "$CONF_OUT_RAW" == "TRUE" ]] && CONF_OUT="true" || CONF_OUT="false"
    
    BOOT_LOGO=$(get_setting "BOOT_LOGO" | tr '[:lower:]' '[:upper:]')
}

# === POMOCNÉ FUNKCE ===

