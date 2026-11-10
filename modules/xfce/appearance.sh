#!/bin/bash
# shellcheck shell=bash
# Vzhled: téma, tapeta, názvy aplikací, klávesové zkratky.

xfce_appearance() {
    log "Nasazuji vzhled XFCE (konfigurace + ikony panelu)..."

    pkill -x xfce4-panel 2>/dev/null || true
    pkill -x xfconfd    2>/dev/null || true
    sleep 1

    local XFCE_CONF_SRC="$CONTENTS_DIR/xfce/config/xfce4"
    local TARGET_CONF_DIR="$USER_HOME/.config/xfce4"

    # 1. Uklidit běžícího démona, ať nepřepíše XML
    killall xfconfd 2>/dev/null || true

    # 2. Čistý start konfigurace
    rm -rf "$TARGET_CONF_DIR" 2>/dev/null || true
    mkdir -p "$USER_HOME/.config"

    if [ -d "$XFCE_CONF_SRC" ]; then
        [ -d "$XFCE_CONF_SRC/xfwm4" ] || mkdir -p "$XFCE_CONF_SRC/xfwm4"
        cp -f "$CONTENTS_DIR/xfce/config/window-titles.conf" "$XFCE_CONF_SRC/xfwm4/" 2>/dev/null || true
        cp -r "$XFCE_CONF_SRC" "$USER_HOME/.config/"
        log "XFCE konfigurace nasazena do $TARGET_CONF_DIR"
    else
        log "CHYBA: $XFCE_CONF_SRC nenalezeno!"
    fi

    # 3. Ikony pro panel (systémově, ne do profilu)
    xfce_panel_icons

    # 4. Vlastnictví
    chown -R "$REAL_USER:$REAL_USER" "$USER_HOME/.config" 2>/dev/null || true

    # Odstranění Open Terminal Here
    install -d -m 755 "$USER_HOME/.config/Thunar"
    install -m 644 "$CONTENTS_DIR/xfce/config/Thunar/uca.xml" \
                "$USER_HOME/.config/Thunar/uca.xml"
    chown "$REAL_USER:$REAL_USER" "$USER_HOME/.config/Thunar/uca.xml"
}


xfce_app_names() {
    # Změna názvu u aplikací pro uživatelskou intuitivnost

    local LOCAL_APPS="$USER_HOME/.local/share/applications"
    
    if [ "$DESKTOP_ENV" == "XFCE" ]; then
        local APP_NAMES_CONF="$CONTENTS_DIR/xfce/config/app-names.conf"
    else
        local APP_NAMES_CONF="$CONTENTS_DIR/lxqt/config/app-names.conf"
    fi
    
    if [ -f "$APP_NAMES_CONF" ]; then
        log "Aplikuji české a intuitivní názvy aplikací z app-names.conf..."
        local CURRENT_DESKTOP=""
        
        while IFS= read -r line || [ -n "$line" ]; do
            # Vyčištění řádku od bílých znaků a \r (Windows formátování)
            line=$(echo "$line" | tr -d '\r' | xargs)
            
            # Přeskočení prázdných řádků a komentářů
            [[ -z "$line" || "$line" =~ ^# ]] && continue
            
            # Detekce sekce [neco.desktop]
            if [[ "$line" =~ ^\[(.*\.desktop)\]$ ]]; then
                CURRENT_DESKTOP="${BASH_REMATCH[1]}"
                
                # Pokud spouštěč v lokální složce ještě není, zkusíme ho stáhnout ze systému
                if [ ! -f "$LOCAL_APPS/$CURRENT_DESKTOP" ] && [ -f "/usr/share/applications/$CURRENT_DESKTOP" ]; then
                    cp "/usr/share/applications/$CURRENT_DESKTOP" "$LOCAL_APPS/" || true
                fi
                
            # Zpracování klíč=hodnota, pokud máme aktivní a existující desktop soubor
            elif [ -n "$CURRENT_DESKTOP" ] && [ -f "$LOCAL_APPS/$CURRENT_DESKTOP" ] && [[ "$line" == *"="* ]]; then
            KEY="${line%%=*}"
            VALUE="${line#*=}"
            
            # OPRAVA: Převede Name[cs] na Name\[cs\], aby to sed pochopil doslovně
            SAFE_KEY=$(echo "$KEY" | sed 's/\[/\\[/g; s/\]/\\]/g')
            
            # 1. Odstraní z cílového souboru původní řádek (aby se to netlouklo)
            sed -i "/^${SAFE_KEY}=/d" "$LOCAL_APPS/$CURRENT_DESKTOP"
            
            # 2. Vloží nový řádek z tvého conf souboru hned pod [Desktop Entry]
            sed -i "/^\[Desktop Entry\]/a ${KEY}=${VALUE}" "$LOCAL_APPS/$CURRENT_DESKTOP"
            
            echo "  -> Nastaveno: $KEY=$VALUE"
        fi
        done < "$APP_NAMES_CONF"
        
        # Oprava vlastnictví pro jistotu a vynucený update databáze spouštěčů
        chown -R "$REAL_USER:$REAL_USER" "$LOCAL_APPS" 2>/dev/null || true
        su - "$REAL_USER" -c "update-desktop-database ~/.local/share/applications" || true
    else
        log "UPOZORNĚNÍ: Soubor $APP_NAMES_CONF nebyl nalezen."
    fi
}


xfce_keyboard_shortcuts() {
    local conf_file="$CONTENTS_DIR/xfce/config/shortcuts.conf"
    local label shortcut command key xfce_shortcut i last_cmd=""

    if [ ! -f "$conf_file" ]; then
        log "UPOZORNĚNÍ: Soubor se zkratkami nenalezen: $conf_file"
        return
    fi

    local tmp
    tmp=$(mktemp /tmp/xfce-shortcuts.XXXXXX)
    echo '#!/bin/bash' > "$tmp"

    local label shortcut command key xfce_shortcut i
    while IFS='|' read -r label shortcut command || [ -n "$label" ]; do
        label=$(echo "$label" | tr -d '\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
        shortcut=$(echo "$shortcut" | tr -d '\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
        command=$(echo "$command" | tr -d '\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

        [[ -z "$label" || "$label" =~ ^# ]] && continue
        [ -z "$shortcut" ] && continue

        local PARTS=()
        IFS='+' read -ra PARTS <<< "$shortcut"
        xfce_shortcut=""

        for i in "${!PARTS[@]}"; do
            key="${PARTS[$i]}"

            if [[ "$key" == "Ctrl" || "$key" == "Control" ]]; then
                key="Primary"
            fi

            if [ "$i" -eq $((${#PARTS[@]} - 1)) ]; then
                if [ ${#key} -eq 1 ]; then
                    key=$(echo "$key" | tr '[:upper:]' '[:lower:]')
                elif [[ "$key" == "Super" || "$key" == "Win" ]]; then
                    key="Super_L"
                fi
                xfce_shortcut="${xfce_shortcut}${key}"
            else
                xfce_shortcut="${xfce_shortcut}<${key}>"
            fi
        done

        log "Zkratka: $xfce_shortcut -> $command"
        last_cmd="$command"
        printf 'xfconf-query -c xfce4-keyboard-shortcuts -p %q -n -t string -s %q\n' \
            "/commands/custom/$xfce_shortcut" "$command" >> "$tmp"
    done < "$conf_file"

    mkdir -p "$USER_HOME/.config/xfce4/xfconf/xfce-perchannel-xml"
    chown -R "$REAL_USER:$REAL_USER" "$USER_HOME/.config/xfce4"
    chmod 755 "$tmp"
    chown "$REAL_USER:$REAL_USER" "$tmp"

    local uid
    uid=$(id -u "$REAL_USER")
    if [ -S "/run/user/$uid/bus" ]; then
        # běžící relace uživatele: zapisuje se přímo do ní
        su - "$REAL_USER" -c "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$uid/bus bash '$tmp'"
    else
        # čerstvá instalace bez relace: dočasná sběrnice
        su - "$REAL_USER" -c "dbus-run-session -- bash -c 'bash \"$tmp\"; sleep 3'"
    fi

    # Počkáme, až xfconfd zapíše změny do XML (zapisuje se se zpožděním)
    local xml="$USER_HOME/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-keyboard-shortcuts.xml"
    local waited=0
    while [ -n "$last_cmd" ] && ! grep -qF -- "$last_cmd" "$xml" 2>/dev/null; do
        sleep 0.5
        waited=$((waited + 1))
        if [ "$waited" -ge 40 ]; then
            log "VAROVÁNÍ: zkratky se do $xml nezapsaly do 20 s!"
            break
        fi
    done

    rm -f "$tmp"
}

