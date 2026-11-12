#!/bin/bash
# shellcheck shell=bash
# Aplikace: nasazení skriptů, .desktop soubory, akce, autostart.

xfce_deploy_scripts() {
    local SCRIPTS_SRC="$CONTENTS_DIR/xfce/scripts"
    local f

    [ -d "$SCRIPTS_SRC" ] || { log "VAROVÁNÍ: $SCRIPTS_SRC nenalezeno"; return 0; }

    for f in "$SCRIPTS_SRC"/*; do
        [ -f "$f" ] || continue
        install -m 755 -o root -g root "$f" /usr/local/bin/
    done
}


xfce_setup_apps_and_defaults() {
    log "Nastavuji chování aplikací, skrytí bloatware a ikony pro XFCE..."
    
    local LOCAL_APPS="$USER_HOME/.local/share/applications"
    mkdir -p "$LOCAL_APPS"
    
    # 1. Zkopírování vybraných systémových spouštěčů do uživatelského prostoru,
    # aby je bylo možné bezpečně upravit (skrýt) bez zásahu do celého systému.
    for app in /usr/share/applications/*.desktop; do
        [ -e "$app" ] || continue
        app_name=$(basename "$app")
        # Kopírujeme jen pokud už tam není, nebo jej chceme přepsat
        if [ ! -f "$LOCAL_APPS/$app_name" ]; then
            cp "$app" "$LOCAL_APPS/" || true
        fi
    done

    # Chrome/Chromium bez dotazu na klíčenku (gnome-keyring)
    local chrome_desktop="$LOCAL_APPS/google-chrome.desktop"
    if [ -f "$chrome_desktop" ]; then
        sed -i 's|google-chrome-stable %U|google-chrome-stable --password-store=basic --no-default-browser-check %U|g' "$chrome_desktop" || true
    fi
    local chromium_desktop="$LOCAL_APPS/chromium.desktop"
    if [ -f "$chromium_desktop" ]; then
        sed -i 's|chromium %U|chromium --password-store=basic --no-default-browser-check %U|g' "$chromium_desktop" || true
    fi

    # 2. Skrytí aplikací definovaných v sekci [APPS_TO_HIDE] v xfce/config.txt
    local APPS_TO_HIDE_STR
    APPS_TO_HIDE_STR=$(get_section "$DESKTOP_CONFIG" "APPS_TO_HIDE" | tr -d '\r')

    for app in $APPS_TO_HIDE_STR; do
        local target_desktop="$LOCAL_APPS/$app"
        # Pokud soubor není v lokální složce, zkusíme ho vzít ze systémové
        if [ ! -f "$target_desktop" ] && [ -f "/usr/share/applications/$app" ]; then
            cp "/usr/share/applications/$app" "$target_desktop"
        fi

        if [ -f "$target_desktop" ]; then
            desktop_hide "$target_desktop"
            log "Skryta aplikace: $app"
        else
            log "UPOZORNĚNÍ: Aplikace $app k zacištění nebyla nalezena."
        fi
    done

    # 3. Autostart podle sekce [AUTORUN] v config.txt
    autostart_sync "$DESKTOP_CONFIG"

    # 3.5 Doplnění StartupNotify=true (pokud v souboru chybí)
    local f
    for f in "$LOCAL_APPS"/*.desktop; do
        [ -f "$f" ] || continue
        grep -q '^\[Desktop Entry\]' "$f" || continue
        desktop_ensure_key "$f" StartupNotify true
    done
    log "Doplněno StartupNotify=true tam, kde chybělo."
    
    # 4. Aktualizace desktopové databáze, aby menu (Whisker) okamžitě reflektovalo změny
    chown -R "$REAL_USER:$REAL_USER" "$LOCAL_APPS" 2>/dev/null || true
    su - "$REAL_USER" -c "update-desktop-database ~/.local/share/applications" || true

        # Zamezení možnosti odinstalace
    echo ">> Ukládám seznam neodstranitelných aplikací..."
    
    # Použití tvé elegantní funkce pro vytažení sekce (taháme z DESKTOP_CONFIG pro LXQt!)
    LOCAL_UNREMOVABLE=$(get_section "$DESKTOP_CONFIG" "UNREMOVABLE")
    
    if [ -n "$LOCAL_UNREMOVABLE" ]; then
        # Vezmeme výstup, smažeme Windows znaky (\r) a nahradíme mezery novým řádkem (\n)
        echo "$LOCAL_UNREMOVABLE" | tr -d '\r' | tr ' ' '\n' > /etc/dapeos-unremovable.txt
        
        chmod 644 /etc/dapeos-unremovable.txt
        echo ">> Obsah uloženého blacklistu:"
        cat /etc/dapeos-unremovable.txt
    else
        echo ">> Seznam [UNREMOVABLE] je prázdný, soubor nebyl vytvořen."
        # Vytvoření prázdného souboru pro jistotu, aby systém neřval, že chybí
        touch /etc/dapeos-unremovable.txt
        chmod 644 /etc/dapeos-unremovable.txt
    fi

    # Kategorie pro tiskárny, aby se zobrazily v nastavení XFCE
    DESKTOP_FILE="$LOCAL_APPS/system-config-printer.desktop"
    if [ -f "$DESKTOP_FILE" ]; then
        desktop_add_category "$DESKTOP_FILE" XFCE X-XFCE-SettingsDialog X-XFCE-HardwareSettings
    else
        log "UPOZORNĚNÍ: $DESKTOP_FILE nenalezen."
    fi
}


xfce_actions_config() {
    # Zástupci z actions.conf - OPRAVENÁ VERZE (Custom Filenames)
    local LOCAL_APPS_DIR="$USER_HOME/.local/share/applications"
    mkdir -p "$LOCAL_APPS_DIR"

    if [ "$DESKTOP_ENV" == "XFCE" ]; then
        local SRC_ACTIONS="$CONTENTS_DIR/xfce/config/actions.conf"
    else
        local SRC_ACTIONS="$CONTENTS_DIR/lxqt/config/actions.conf"
    fi
    
    
    if [ -f "$SRC_ACTIONS" ]; then
        local BLOCK=""
        local APP_NAME=""
        local CUSTOM_FILENAME=""
        
        # Načítáme soubor řádek po řádku
        while IFS= read -r line || [ -n "$line" ]; do
            # Oříznutí bílých znaků (včetně neviditelných \r z Windows)
            trimmed=$(echo "$line" | tr -d '\r' | xargs)
            
            # 1. Zachycení našeho vlastního jména souboru
            if [[ "$trimmed" == \[FileName=*\] ]]; then
                # Pokud už máme uložený předchozí blok, zapíšeme ho
                if [ -n "$BLOCK" ]; then
                    local TARGET_FILE="${CUSTOM_FILENAME:-$(echo "$APP_NAME" | tr '[:upper:]' '[:lower:]' | sed -e 's/ /-/g' -e 's/[^a-z0-9-]//g')}"
                    [ -z "$TARGET_FILE" ] && TARGET_FILE="unknown-app-$(date +%s%N)"
                    
                    echo -e "$BLOCK" > "$LOCAL_APPS_DIR/${TARGET_FILE}.desktop"
                    chmod +x "$LOCAL_APPS_DIR/${TARGET_FILE}.desktop"
                fi
                
                # Vytažení samotného jména (odstranění [FileName= a ])
                CUSTOM_FILENAME="${trimmed#\[FileName=}"
                CUSTOM_FILENAME="${CUSTOM_FILENAME%\]}"
                
                # Resetujeme buffer, protože hned po tomhle by mělo následovat [Desktop Entry]
                BLOCK=""
                APP_NAME=""
                continue
            fi
            
            # 2. Zachycení začátku bloku zástupce (Pokud tam není FileName)
            if [[ "$trimmed" == "[Desktop Entry]" ]]; then
                # Zápis předchozího bloku (pojistka, pokud někdo vynechal [FileName=])
                if [ -n "$BLOCK" ]; then
                    local TARGET_FILE="${CUSTOM_FILENAME:-$(echo "$APP_NAME" | tr '[:upper:]' '[:lower:]' | sed -e 's/ /-/g' -e 's/[^a-z0-9-]//g')}"
                    [ -z "$TARGET_FILE" ] && TARGET_FILE="unknown-app-$(date +%s%N)"
                    
                    echo -e "$BLOCK" > "$LOCAL_APPS_DIR/${TARGET_FILE}.desktop"
                    chmod +x "$LOCAL_APPS_DIR/${TARGET_FILE}.desktop"
                    CUSTOM_FILENAME=""
                fi
                BLOCK="[Desktop Entry]"
                APP_NAME=""
                
            # 3. Zpracování vnitřku bloku
            elif [ -n "$BLOCK" ] && [ -n "$trimmed" ]; then
                local processed_line="${line//~\/.local/$USER_HOME\/.local}"
                BLOCK="${BLOCK}\n${processed_line}"
                
                if [[ "$processed_line" == Name=* ]]; then
                    APP_NAME="${processed_line#Name=}"
                fi
            fi
        done < "$SRC_ACTIONS"
        
        # Nezapomenout uložit úplně poslední blok ze souboru!
        if [ -n "$BLOCK" ]; then
            local TARGET_FILE="${CUSTOM_FILENAME:-$(echo "$APP_NAME" | tr '[:upper:]' '[:lower:]' | sed -e 's/ /-/g' -e 's/[^a-z0-9-]//g')}"
            [ -z "$TARGET_FILE" ] && TARGET_FILE="unknown-app-$(date +%s%N)"
            
            echo -e "$BLOCK" > "$LOCAL_APPS_DIR/${TARGET_FILE}.desktop"
            chmod +x "$LOCAL_APPS_DIR/${TARGET_FILE}.desktop"
        fi
    fi
}

