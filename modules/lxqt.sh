#!/bin/bash
# shellcheck shell=bash
# LXQt: původní větev (konzervováno, nepoužívá se).

lxqt_setup_apps_and_defaults() {
    log "6/8: Nastavuji chování aplikací, MIME typy, Prohlížeč a Autostart..."
    
    local LOCAL_APPS="$USER_HOME/.local/share/applications"
    local WRAPPER_BIN="$USER_HOME/.local/bin/busy-launch.py"
    mkdir -p "$LOCAL_APPS"
    
    # Nasazení wrapperů
    for app in /usr/share/applications/*.desktop; do
        [ -e "$app" ] || continue
        app_name=$(basename "$app")
        cp "$app" "$LOCAL_APPS/" || true
        sed -i "s|^Exec=|Exec=python3 $WRAPPER_BIN |" "$LOCAL_APPS/$app_name" || true
    done

    # Skrytí aplikací
    local APPS_TO_HIDE_STR
    APPS_TO_HIDE_STR=$(get_section "$DESKTOP_CONFIG" "APPS_TO_HIDE" | tr -d '\r')
    for app in $APPS_TO_HIDE_STR; do
        [ -f "$LOCAL_APPS/$app" ] && sed -i '/^NoDisplay=/d; $ a NoDisplay=true' "$LOCAL_APPS/$app" || true
    done

    # Zobrazení aplikací: smazání OnlyShowIn / NotShowIn / NoDisplay
    local APPS_TO_SHOW_STR
    APPS_TO_SHOW_STR=$(get_section "$DESKTOP_CONFIG" "APPS_TO_SHOW" | tr -d '\r')
    for app in $APPS_TO_SHOW_STR; do
        if [ -f "$LOCAL_APPS/$app" ]; then
            sed -i '/^OnlyShowIn=/d; /^NotShowIn=/d; /^NoDisplay=/d; /^X-XfceSettingsManagerHidden=/d' "$LOCAL_APPS/$app"
            log "Zobrazeno: $app"
        else
            log "UPOZORNĚNÍ: $app nenalezen v $LOCAL_APPS"
        fi
    done

    mkdir -p "$USER_HOME/.config/dapeos"
    printf '%s\n' $APPS_TO_SHOW_STR > "$USER_HOME/.config/dapeos/apps-show.list"
    chown -R "$REAL_USER:$REAL_USER" "$USER_HOME/.config/dapeos"

    # Aktualizace MIME mezipaměti (až po všech úpravách .desktop souborů)
    log "Aktualizuji lokální MIME databázi pro zástupce s wrappery..."
    su - "$REAL_USER" -c "update-desktop-database ~/.local/share/applications" || true

    # --- IDENTIFIKACE A UMLČENÍ ZVOLENÉHO PROHLÍŽEČE ---
    local BROWSER_DESKTOP=""
    local BROWSER_BIN=""
    if [ "$BROWSER_CHOICE" != "5" ] && [ -n "$BROWSER_CHOICE" ]; then
        case "$BROWSER_CHOICE" in
            1) BROWSER_DESKTOP="google-chrome.desktop"; BROWSER_BIN="/usr/bin/google-chrome" ;;
            2) BROWSER_DESKTOP="chromium.desktop"; BROWSER_BIN="/usr/bin/chromium" ;;
            3) BROWSER_DESKTOP="brave-browser.desktop"; BROWSER_BIN="/usr/bin/brave-browser" ;;
            4) BROWSER_DESKTOP="firefox-esr.desktop"; [ -x "/usr/bin/firefox" ] && BROWSER_BIN="/usr/bin/firefox" || BROWSER_BIN="/usr/bin/firefox-esr" ;;
        esac

        if [ "$BROWSER_DESKTOP" = "google-chrome.desktop" ] && [ -f "$LOCAL_APPS/google-chrome.desktop" ]; then
            sed -i 's/google-chrome-stable %U/google-chrome-stable --password-store=basic --no-default-browser-check %U/g' "$LOCAL_APPS/google-chrome.desktop" || true
        fi

        if [ "$BROWSER_DESKTOP" = "chromium.desktop" ] && [ -f "$LOCAL_APPS/chromium.desktop" ]; then
            sed -i 's/chromium %U/chromium --password-store=basic --no-default-browser-check %U/g' "$LOCAL_APPS/chromium.desktop" || true
        fi

        log "Nastavuji $BROWSER_DESKTOP jako systémový default a potlačuji hlášky..."
        su - "$REAL_USER" -c "xdg-settings set default-web-browser $BROWSER_DESKTOP 2>/dev/null" || true
        su - "$REAL_USER" -c "xdg-mime default $BROWSER_DESKTOP x-scheme-handler/http 2>/dev/null" || true
        su - "$REAL_USER" -c "xdg-mime default $BROWSER_DESKTOP x-scheme-handler/https 2>/dev/null" || true
        
        if [ "$BROWSER_CHOICE" == "1" ]; then
            log "Vynucuji firemní politiku pro umlčení Chrome hlášky..."
            mkdir -p /etc/opt/chrome/policies/managed
            echo '{"DefaultBrowserSettingEnabled": false}' > /etc/opt/chrome/policies/managed/default_browser.json
        fi

        if [ -x "$BROWSER_BIN" ]; then
            update-alternatives --set x-www-browser "$BROWSER_BIN" 2>/dev/null || true
            update-alternatives --set gnome-www-browser "$BROWSER_BIN" 2>/dev/null || true
        fi
    fi

    # --- MIME Typy ---
    local MIME_FILE="$USER_HOME/.config/mimeapps.list"
    [ ! -f "$MIME_FILE" ] && echo "[Added Associations]" > "$MIME_FILE"
    grep -q "^\[Added Associations\]" "$MIME_FILE" || echo "[Added Associations]" >> "$MIME_FILE"

    set_default_app() {
        local mime="$1"
        local app="$2"
        sed -i "/^${mime//\//\\/}=/d" "$MIME_FILE" 2>/dev/null || true
        sed -i "/^\[Added Associations\]/a ${mime}=${app};" "$MIME_FILE"
    }

    local APPS_CONF="$CONTENTS_DIR/lxqt/config/defaultapps.conf"
    
    if [ -f "$APPS_CONF" ]; then
        log "Načítám výchozí aplikace z defaultapps.conf..."
        local CURRENT_APP=""
        
        while IFS= read -r line || [ -n "$line" ]; do
            line=$(echo "$line" | xargs)
            [[ -z "$line" || "$line" =~ ^# ]] && continue
            
            if [[ "$line" =~ ^\[(.*)\]$ ]]; then
                CURRENT_APP="${BASH_REMATCH[1]}"
                
                if [ "$CURRENT_APP" == "wine.desktop" ] && [ "$WINE_REQ" != "TRUE" ]; then
                    CURRENT_APP="SKIP"
                elif [[ "$CURRENT_APP" == *"libreoffice"* ]] && [ "$OFFICE_CHOICE" != "1" ]; then
                    CURRENT_APP="SKIP"
                elif [[ "$CURRENT_APP" == *"onlyoffice"* ]] && [ "$OFFICE_CHOICE" != "2" ]; then
                    CURRENT_APP="SKIP"
                elif [[ "$CURRENT_APP" =~ (google-chrome|chromium|brave-browser|firefox) ]]; then
                    if [ "$CURRENT_APP" != "$BROWSER_DESKTOP" ]; then
                        CURRENT_APP="SKIP"
                    fi
                fi
                
            elif [ "$CURRENT_APP" != "SKIP" ] && [ -n "$CURRENT_APP" ]; then
                set_default_app "$line" "$CURRENT_APP"
            fi
        done < "$APPS_CONF"
    else
        log "UPOZORNĚNÍ: Soubor $APPS_CONF nebyl nalezen, výchozí aplikace nebudou nastaveny."
    fi

    # Autostart
    local AUTOSTART_DIR="$USER_HOME/.config/autostart"
    mkdir -p "$AUTOSTART_DIR"
    AUTORUN_APPS=$(awk '/^\[AUTORUN\]/{flag=1; next} /^\[/{flag=0} flag && NF' "$DESKTOP_CONFIG" | tr -d '\r')

    if [ -n "$AUTORUN_APPS" ]; then
        for APP in $AUTORUN_APPS; do
            local DEST_DESKTOP="$AUTOSTART_DIR/${APP}-autostart.desktop"
            local EXEC_CMD="$APP"
            
            if [[ "$APP" == *.sh || "$APP" == *.py ]]; then
                EXEC_CMD="$APP"
            fi
            
            echo "[Desktop Entry]" > "$DEST_DESKTOP"
            echo "Type=Application" >> "$DEST_DESKTOP"
            echo "Name=Autostart $APP" >> "$DEST_DESKTOP"
            echo "Exec=$EXEC_CMD" >> "$DEST_DESKTOP"
            echo "Hidden=false" >> "$DEST_DESKTOP"
            echo "NoDisplay=false" >> "$DEST_DESKTOP"
            echo "X-GNOME-Autostart-enabled=true" >> "$DEST_DESKTOP"
        done
    fi

    albert_peazip_config
    app_names

    # Ošetření práv na závěr
    chown -R "$REAL_USER:$REAL_USER" "$USER_HOME/.config" "$USER_HOME/.local" 2>/dev/null || true
}


lxqt_prepare_base_configs() {
    log "1/8: Připravuji základní konfigurační soubory LXQt..."
    
    # Odstranění Windows konců řádků
    [ -f "$CONTENTS_DIR/lxqt/config/shortcuts.conf" ] && sed -i 's/\r$//' "$CONTENTS_DIR/lxqt/config/shortcuts.conf" || true
    [ -f "$CONTENTS_DIR/lxqt/config/xfwm.conf" ] && sed -i 's/\r$//' "$CONTENTS_DIR/lxqt/config/xfwm.conf" || true
    [ -f "$CONTENTS_DIR/lxqt/config/contextmenu.conf" ] && sed -i 's/\r$//' "$CONTENTS_DIR/lxqt/config/contextmenu.conf" || true
    [ -f "$CONTENTS_DIR/lxqt/config/lxqt-powermanagement.conf" ] && sed -i 's/\r$//' "$CONTENTS_DIR/lxqt/config/lxqt-powermanagement.conf" || true

    # Kopírování základu
    local CONF_SRC="$CONTENTS_DIR/lxqt/config"
    mkdir -p "$USER_HOME/.config/lxqt" "$USER_HOME/.config/pcmanfm-qt/lxqt"
    cp "$CONF_SRC/"*.conf "$USER_HOME/.config/lxqt/" 2>/dev/null || true
    cp "$CONF_SRC/pcmanfm-qt.conf" "$USER_HOME/.config/pcmanfm-qt/lxqt/settings.conf" 2>/dev/null || true

    # Základní nastavení LXQt a sjednocení vzhledu (Jako v Lubuntu)
    local LXQT_CONF="$USER_HOME/.config/lxqt/lxqt.conf"
    mkdir -p "$(dirname "$LXQT_CONF")"
    
    # Pojistka, kdyby soubor vůbec neexistoval
    if [ ! -f "$LXQT_CONF" ]; then
        echo "[General]" > "$LXQT_CONF"
    fi

    # 5. Jazyk
    if grep -q "^language=" "$LXQT_CONF"; then
        sed -i "s/^language=.*/language=$SYS_LANG_CODE/" "$LXQT_CONF" || true
    else
        sed -i "/^\[General\]/a language=$SYS_LANG_CODE" "$LXQT_CONF" || true
    fi
    
    # 6. Smazání paměti Trolltech (ZÁSADNÍ: aby Qt framework nelepil staré tmavé barvy na nová světla okna)
    rm -f "$USER_HOME/.config/Trolltech.conf" || true

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

    # QTerminal nenápadně stranou
    local Q_CONF="$USER_HOME/.config/qterminal.org/qterminal.ini"
    mkdir -p "$(dirname "$Q_CONF")"
    [ ! -f "$Q_CONF" ] && echo -e "[General]\nshowTerminalSizeHint=false\nAskOnExit=false" > "$Q_CONF" || sed -i '/showTerminalSizeHint/d; /AskOnExit/d; /\[General\]/a showTerminalSizeHint=false\nAskOnExit=false' "$Q_CONF" || true

    # QPS konfigurace
    local QPS_DST_DIR="$USER_HOME/.config/qps"
    mkdir -p "$QPS_DST_DIR"
    if [ -f "$CONF_SRC/qps.conf" ]; then
        cp "$CONF_SRC/qps.conf" "$QPS_DST_DIR/qps.conf"
    fi

    # Flameshot konfigurace (přejmenování .conf na .ini)
    local FLAMESHOT_DST_DIR="$USER_HOME/.config/flameshot"
    mkdir -p "$FLAMESHOT_DST_DIR"
    if [ -f "$CONF_SRC/flameshot.conf" ]; then
        cp "$CONF_SRC/flameshot.conf" "$FLAMESHOT_DST_DIR/flameshot.ini"
    fi
}


lxqt_setup_system_integrations() {
    log "2/8: Nasazuji systémové integrace (Skripty, APT hook, Locale, Polkit, NM-Tray)..."
    
    local SCRIPTS_SRC="$CONTENTS_DIR/lxqt/scripts"
    mkdir -p "$USER_HOME/.local/bin"
    if [ -d "$SCRIPTS_SRC" ]; then
        cp -u "$SCRIPTS_SRC/"* "$USER_HOME/.local/bin/" 2>/dev/null || true
        chmod +x "$USER_HOME/.local/bin/"* 2>/dev/null || true
    fi

    echo "DPkg::Post-Invoke { \"su - $REAL_USER -c '$USER_HOME/.local/bin/update-wrappers.sh'\"; };" > /etc/apt/apt.conf.d/99-update-wrappers
    
    chmod +s $(which brightnessctl 2>/dev/null) 2>/dev/null || true
    rm -f "/tmp/jas_notif_id" || true
    if ! grep -q ".local/bin" "$USER_HOME/.bashrc"; then
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$USER_HOME/.bashrc"
    fi

    echo "export LANG=$SYS_LOCALE" > /etc/profile.d/00-locale.sh
    echo "export LC_ALL=$SYS_LOCALE" >> /etc/profile.d/00-locale.sh

    mkdir -p /etc/polkit-1/rules.d
    echo 'polkit.addRule(function(action, subject) { if ((action.id == "org.freedesktop.udisks2.filesystem-mount-system" || action.id == "org.freedesktop.udisks2.filesystem-mount") && subject.isInGroup("sudo")) { return polkit.Result.YES; } });' > /etc/polkit-1/rules.d/50-udisks2-automount.rules

    local TOUCHPAD_SRC="$CONTENTS_DIR/lxqt/config/touchpad.conf"
    mkdir -p /etc/X11/xorg.conf.d
    if [ -f "$TOUCHPAD_SRC" ]; then
        cp "$TOUCHPAD_SRC" /etc/X11/xorg.conf.d/40-libinput-touchpad.conf || true
    fi

    # --- OPRAVA NM-TRAY  ---
    log "Přesměrovávám nm-tray na Gnome editor a blokuji duplicitní ikonu..."
    
    # 1. Přesměrování editoru
    local NM_TRAY_DIR="$USER_HOME/.config/nm-tray"
    mkdir -p "$NM_TRAY_DIR"
    local NM_TRAY_CONF="$NM_TRAY_DIR/nm-tray.conf"
    
    if [ ! -f "$NM_TRAY_CONF" ]; then
        echo -e "[general]\nconnectionsEditor=nm-connection-editor" > "$NM_TRAY_CONF"
    else
        sed -i '/^connectionsEditor=/d' "$NM_TRAY_CONF"
        sed -i '/^\[general\]/a connectionsEditor=nm-connection-editor' "$NM_TRAY_CONF" 2>/dev/null || echo -e "\n[general]\nconnectionsEditor=nm-connection-editor" >> "$NM_TRAY_CONF"
    fi
    
    # 2. Likvidace duplicitní ikony z autostartu
    local AUTOSTART_DIR="$USER_HOME/.config/autostart"
    mkdir -p "$AUTOSTART_DIR"
    echo -e "[Desktop Entry]\nHidden=true" > "$AUTOSTART_DIR/nm-applet.desktop"

    mkdir -p /etc/polkit-1/rules.d
    printf 'polkit.addRule(function(action, subject) {\n    if ((action.id == "org.freedesktop.systemd1.manage-units" || \n         action.id == "org.freedesktop.systemd1.manage-unit-files") &&\n        subject.isInGroup("sudo")) {\n        var unit = action.lookup("unit");\n        if (unit == "rustdesk.service" || unit == "rustdesk") {\n            return polkit.Result.YES;\n        }\n    }\n});\n' > /etc/polkit-1/rules.d/60-rustdesk.rules

    # Passwd manažer
    echo "$USER ALL=(ALL) NOPASSWD: /usr/bin/passwd, /usr/sbin/chpasswd, /bin/rm, /bin/mkdir, /bin/bash" | sudo tee /etc/sudoers.d/99-gui-pass-manager
    sudo chmod 0440 /etc/sudoers.d/99-gui-pass-manager

    log "Vytvářím automatický odklepávač důvěry pro zástupce na ploše..."
    mkdir -p "$USER_HOME/.local/bin"
    mkdir -p "$USER_HOME/.config/autostart"
    
    # --- AUTOMATICKÉ POVOLOVÁNÍ ZÁSTUPCŮ (Desktop Trust) ---
    log "Nasazuji hlídací skript pro automatické důvěřování zástupcům na ploše..."

    # 1. Instalace závislosti (pokud by náhodou v systému chyběla)
    apt-get install -y inotify-tools || true

    # 2. Vytvoření složek
    mkdir -p "$USER_HOME/.local/bin"
    mkdir -p "$USER_HOME/.config/autostart"

    local TRUST_SCRIPT="$USER_HOME/.local/bin/desktop-trust.sh"

    # 3. Zápis hlídacího skriptu (BEZ EOF, s tvým vítězným GIO příkazem)
    echo '#!/bin/bash' > "$TRUST_SCRIPT"
    echo 'DESKTOP_DIR=$(xdg-user-dir DESKTOP)' >> "$TRUST_SCRIPT"
    echo '[ -z "$DESKTOP_DIR" ] && DESKTOP_DIR="$HOME/Desktop"' >> "$TRUST_SCRIPT"
    echo 'while [ ! -d "$DESKTOP_DIR" ]; do sleep 2; done' >> "$TRUST_SCRIPT"
    echo '' >> "$TRUST_SCRIPT"
    echo 'inotifywait -m -q -e create,moved_to "$DESKTOP_DIR" --format "%w%f" | while read -r filepath; do' >> "$TRUST_SCRIPT"
    echo '    if [[ "$filepath" == *.desktop ]]; then' >> "$TRUST_SCRIPT"
    echo '        # Krátká pauza, aby se soubor stihl fyzicky zapsat na disk' >> "$TRUST_SCRIPT"
    echo '        sleep 0.5' >> "$TRUST_SCRIPT"
    echo '        # Tvůj ověřený příkaz pro LXQt trust' >> "$TRUST_SCRIPT"
    echo '        gio set "$filepath" -t string metadata::trust true 2>/dev/null' >> "$TRUST_SCRIPT"
    echo '        chmod +x "$filepath" 2>/dev/null' >> "$TRUST_SCRIPT"
    echo '    fi' >> "$TRUST_SCRIPT"
    echo 'done' >> "$TRUST_SCRIPT"

    # 4. Nastavení práv pro skript
    chmod +x "$TRUST_SCRIPT"
    chown "$REAL_USER:$REAL_USER" "$TRUST_SCRIPT"

    # 5. Vytvoření Autostartu (aby hlídač naskočil po přihlášení)
    local AUTO_PATH="$USER_HOME/.config/autostart/desktop-trust.desktop"
    echo '[Desktop Entry]' > "$AUTO_PATH"
    echo 'Type=Application' >> "$AUTO_PATH"
    echo 'Name=Desktop Trust Fix' >> "$AUTO_PATH"
    echo "Exec=bash $TRUST_SCRIPT" >> "$AUTO_PATH"
    echo 'Hidden=false' >> "$AUTO_PATH"
    echo 'NoDisplay=false' >> "$AUTO_PATH"
    echo 'X-GNOME-Autostart-enabled=true' >> "$AUTO_PATH"

    # Oprava práv pro autostart
    chown "$REAL_USER:$REAL_USER" "$AUTO_PATH"
    # ------------------------------------------
    
    # Přidání do autostartu LXQt
    echo '[Desktop Entry]' > "$USER_HOME/.config/autostart/desktop-trust.desktop"
    echo 'Type=Application' >> "$USER_HOME/.config/autostart/desktop-trust.desktop"
    echo 'Name=AutoTrust Desktop' >> "$USER_HOME/.config/autostart/desktop-trust.desktop"
    echo "Exec=$USER_HOME/.local/bin/desktop-trust.sh" >> "$USER_HOME/.config/autostart/desktop-trust.desktop"
    echo 'Hidden=false' >> "$USER_HOME/.config/autostart/desktop-trust.desktop"
    
    chown -R "$REAL_USER:$REAL_USER" "$USER_HOME/.local/bin/desktop-trust.sh" "$USER_HOME/.config/autostart/desktop-trust.desktop"
}


lxqt_setup_appearance() {
    log "3/8: Konfiguruji vzhled (stažení motivu, správce oken, panel, ikony)..."
    
    # 1. Stažení a příprava grafických podkladů (Lubuntu Artwork)
    log "Stahuji Lubuntu artwork a nasazuji ikony..."
    cd /tmp && rm -rf lubuntu-rip && mkdir -p lubuntu-rip && cd lubuntu-rip
    
    # 1. SKREPOVÁNÍ PŘES cURL A CZ MIRROR: 
    # --max-time 5 garantuje, že i kdyby server hořel, skript se po 5 vteřinách pohne dál.
    local FILE_NAME=$(curl -s --max-time 5 "http://cz.archive.ubuntu.com/ubuntu/pool/universe/l/lubuntu-artwork/" | grep -o 'lubuntu-artwork_[^"]*_all\.deb' | tail -n 1) || true
    
    if [ -n "$FILE_NAME" ]; then
        log "Nalezen balíček: $FILE_NAME, stahuji z CZ mirroru..."
        
        # 2. RYCHLÉ STAŽENÍ BALÍČKU
        wget -q --timeout=15 --tries=2 "http://cz.archive.ubuntu.com/ubuntu/pool/universe/l/lubuntu-artwork/$FILE_NAME" -O lubuntu-artwork.deb || true
        
        if [ -s lubuntu-artwork.deb ]; then
            dpkg-deb -x lubuntu-artwork.deb root_dir || true
            mkdir -p "$USER_HOME/.local/share/lxqt/themes"
            cp -r root_dir/usr/share/lxqt/themes/* "$USER_HOME/.local/share/lxqt/themes/" 2>/dev/null || true
            log "Lubuntu Artwork úspěšně nasazen."
        else
            log "CHYBA: Stažení balíčku selhalo (soubor je prázdný)."
        fi
    else
        log "CHYBA: CZ Server neodpověděl do 5 vteřin, nepodařilo se zjistit název."
    fi
    
    cd ~ && rm -rf /tmp/lubuntu-rip || true

    local ICONS_SRC="$CONTENTS_DIR/lxqt/icons"
    if [ -d "$ICONS_SRC" ]; then
        cp -r "$ICONS_SRC" "$USER_HOME/.local/share/" 2>/dev/null || true
    fi

    # --- NOVÁ ČÁST: NASAZENÍ VLASTNÍCH IKON A KONFIGURACÍ ---

    # A) Extrakce vlastního balíčku ikon (Papirus-Custom)
    local ICON_ARCHIVE="$CONTENTS_DIR/lxqt/icons/Papirus-Custom.tar.gz"
    if [ -f "$ICON_ARCHIVE" ]; then
        log "Nasazuji vlastní ikony Papirus-Custom (obsahuje fixy pro Blueman a CopyQ)..."
        mkdir -p /usr/share/icons
        tar -xzf "$ICON_ARCHIVE" -C /usr/share/icons/ || true
        gtk-update-icon-cache -f -q /usr/share/icons/Papirus-Custom || true
    else
        log "VAROVANI: Balicek Papirus-Custom.tar.gz nebyl nalezen!"
    fi

    # B) Úprava motivu Lubuntu Arc (Nasazení tvého vlastního lxqt-panel.qss)
    local QSS_SRC="$CONTENTS_DIR/lxqt/config/lxqt-panel.qss"
    local THEME_DIR="$USER_HOME/.local/share/lxqt/themes/Lubuntu Arc"
    if [ -f "$QSS_SRC" ] && [ -d "$THEME_DIR" ]; then
        log "Aplikuji QSS fix pro bile ikony na panelu..."
        cp "$QSS_SRC" "$THEME_DIR/" || true
        chown "$REAL_USER:$REAL_USER" "$THEME_DIR/lxqt-panel.qss" || true
    fi

    # C) Nasazení předpřipravených konfigurací (Vzhled a GTK lock)
    export DISPLAY="${DISPLAY:-:0}"
    export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=/run/user/$(id -u)/bus}"

    local APP_CONF_SRC="$CONTENTS_DIR/lxqt/config/lxqt-config-appearance.conf"
    local LXQT_CONF_DIR="$USER_HOME/.config/lxqt"
    mkdir -p "$LXQT_CONF_DIR"
    
    if [ -f "$APP_CONF_SRC" ]; then
        log "Kopiruji lxqt-config-appearance.conf (GTK lock)..."
        cp "$APP_CONF_SRC" "$LXQT_CONF_DIR/" || true
    fi
    
    # D) Ošetření konfigurace panelu (Uzamčení panelu na Papirus-Dark)
    local PANEL_CONF="$LXQT_CONF_DIR/panel.conf"
    if [ -f "$PANEL_CONF" ]; then
        # Smaže jakýkoliv předchozí iconTheme a práskne tam natvrdo ten Dark
        sed -i '/^iconTheme=/d' "$PANEL_CONF" || true
        sed -i '/^\[General\]/a iconTheme=Papirus-Dark' "$PANEL_CONF" || true
    fi

    # E) Fix pro CopyQ (Pokud se nepoužívá předpřipravený copyq.conf)
    local COPYQ_CONF="$USER_HOME/.config/copyq/copyq.conf"
    if [ -f "$COPYQ_CONF" ]; then
        sed -i 's/use_system_icons=false/use_system_icons=true/' "$COPYQ_CONF" || true
    fi

    # Oprava práv pro jistotu (když skript běží pod rootem)
    chown -R "$REAL_USER:$REAL_USER" "$USER_HOME/.config/lxqt" || true
    
    # --- KONEC NOVÉ ČÁSTI ---
    
    # 2. XFWM4 Session
    local SESSION_CONF="$USER_HOME/.config/lxqt/session.conf"
    if [ ! -f "$SESSION_CONF" ]; then
        echo -e "[General]\nwindow_manager=xfwm4" > "$SESSION_CONF"
    else
        sed -i 's/^window_manager=.*/window_manager=xfwm4/' "$SESSION_CONF" || true
        grep -q "^window_manager=" "$SESSION_CONF" || sed -i '/^\[General\]/a window_manager=xfwm4' "$SESSION_CONF" || true
    fi

    # ZÁCHRANA PRÁV: Zabezpečenie, že celá .config zložka patrí užívateľovi (inak všetko ostatné zlyhá)
    chown -R "$REAL_USER:$REAL_USER" "$USER_HOME/.config" 2>/dev/null || true

    local XFWM_SRC="$CONTENTS_DIR/lxqt/config/xfwm.conf"
    if [ -f "$XFWM_SRC" ]; then
        cp "$XFWM_SRC" /tmp/xfwm-apply.sh
        chown "$REAL_USER:$REAL_USER" /tmp/xfwm-apply.sh
        mkdir -p "$USER_HOME/.config/xfce4/xfconf/xfce-perchannel-xml"
        chown -R "$REAL_USER:$REAL_USER" "$USER_HOME/.config/xfce4"
        # Falošný X11 server (xvfb) oklame xfconf-query, aby nespadol na D-Bus chybe
        su - "$REAL_USER" -c "dbus-run-session -- bash -c 'bash /tmp/xfwm-apply.sh; sleep 3'"
        rm -f /tmp/xfwm-apply.sh
    fi

    # 1. Konfigurace GTK-3 pro Thunar a systém (ikony Papirus, Adwaita, světlý režim)
     # 1. Zápis do gtk-3.0/settings.ini
    sudo -u "$REAL_USER" mkdir -p "$USER_HOME/.config/gtk-3.0"
    sudo -u "$REAL_USER" printf "[Settings]\ngtk-icon-theme-name = Papirus\ngtk-theme-name = Adwaita\ngtk-application-prefer-dark-theme = false\n" > "$USER_HOME/.config/gtk-3.0/settings.ini"

    # 2. Vytvoření složek pro XFCE konfiguraci
    sudo -u "$REAL_USER" mkdir -p "$USER_HOME/.config/xfce4/xfconf/xfce-perchannel-xml"

    # 3. Zápis ikon (Papirus) přímo do xsettings.xml
    sudo -u "$REAL_USER" printf '<?xml version="1.0" encoding="UTF-8"?>\n<channel name="xsettings" version="1.0">\n  <property name="Net" type="empty">\n    <property name="IconThemeName" type="string" value="Papirus"/>\n  </property>\n</channel>\n' > "$USER_HOME/.config/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml"

    # 4. Zápis tapety a viditelnosti ikon na ploše přímo do xfce4-desktop.xml
    sudo -u "$REAL_USER" printf '<?xml version="1.0" encoding="UTF-8"?>\n<channel name="xfce4-desktop" version="1.0">\n  <property name="desktop-icons" type="empty">\n    <property name="icon-theme-name" type="string" value="Papirus"/>\n    <property name="file-icons" type="empty">\n      <property name="show-filesystem" type="bool" value="false"/>\n      <property name="show-trash" type="bool" value="true"/>\n      <property name="show-removable" type="bool" value="false"/>\n    </property>\n  </property>\n  <property name="backdrop" type="empty">\n    <property name="screen0" type="empty">\n      <property name="monitor0" type="empty">\n        <property name="workspace0" type="empty">\n          <property name="last-image" type="string" value="/usr/share/backgrounds/wallpaper.png"/>\n          <property name="image-style" type="int" value="5"/>\n        </property>\n      </property>\n      <property name="monitorVirtual-1" type="empty">\n        <property name="workspace0" type="empty">\n          <property name="last-image" type="string" value="/usr/share/backgrounds/wallpaper.png"/>\n          <property name="image-style" type="int" value="5"/>\n        </property>\n      </property>\n    </property>\n  </property>\n</channel>\n' > "$USER_HOME/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml"


    # 3. Architektura panelu
    local CONF_SRC="$CONTENTS_DIR/lxqt/config"
    if [ "$SYS_ARCH" = "amd64" ] && [ -f "$CONF_SRC/lxqt-panel_no_about_amd64" ]; then
        mv /usr/bin/lxqt-panel /usr/bin/lxqt-panel.bak 2>/dev/null || true
        cp "$CONF_SRC/lxqt-panel_no_about_amd64" /usr/bin/lxqt-panel || true
        chmod +x /usr/bin/lxqt-panel || true
    elif [ "$SYS_ARCH" = "arm64" ] && [ -f "$CONF_SRC/lxqt-panel_no_about_arm64" ]; then
        mv /usr/bin/lxqt-panel /usr/bin/lxqt-panel.bak 2>/dev/null || true
        cp "$CONF_SRC/lxqt-panel_no_about_arm64" /usr/bin/lxqt-panel || true
        chmod +x /usr/bin/lxqt-panel || true
    fi

    # 4. Panel ikony a quicklaunch
    local PANEL_CONF="$USER_HOME/.config/lxqt/panel.conf"
    local LOCAL_APPS="$USER_HOME/.local/share/applications"
    if [ -f "$PANEL_CONF" ]; then
        sed -i "s|icon=~/.local|icon=$USER_HOME/.local|g" "$PANEL_CONF" || true
        
        case $BROWSER_CHOICE in
            1) B_NAME="google-chrome.desktop"; B_EXEC="google-chrome-stable" ;;
            2) B_NAME="chromium.desktop"; B_EXEC="chromium" ;;
            3) B_NAME="brave-browser.desktop"; B_EXEC="brave-browser" ;;
            4) B_NAME="firefox-esr.desktop"; B_EXEC="firefox-esr" ;;
            *) B_NAME=""; B_EXEC="" ;;
        esac

        [ -f "$SESSION_CONF" ] && [ -n "$B_EXEC" ] && sed -i "s/^BROWSER=.*/BROWSER=$B_EXEC/" "$SESSION_CONF" || true

        # Definice názvu zástupce pro vyhledávání (uprav podle reality)
        local SEARCH_DESKTOP="$LOCAL_APPS/albert-search.desktop"

        # Vymazání starých zástupců
        sed -i '/^apps\\/d' "$PANEL_CONF" || true
        
        if [ -n "$B_NAME" ]; then
            # Pokud je prohlížeč: 1. Hledání, 2. PCManFM, 3. Prohlížeč (size=3)
            sed -i "/^\[quicklaunch\]/a apps\\\\1\\\\desktop=$SEARCH_DESKTOP\napps\\\\2\\\\desktop=$LOCAL_APPS/thunar.desktop\napps\\\\3\\\\desktop=$LOCAL_APPS/$B_NAME\napps\\\\size=3" "$PANEL_CONF" || true
        else
            # Pokud není prohlížeč: 1. Hledání, 2. PCManFM (size=2)
            sed -i "/^\[quicklaunch\]/a apps\\\\1\\\\desktop=$SEARCH_DESKTOP\napps\\\\2\\\\desktop=$LOCAL_APPS/thunar.desktop\napps\\\\size=2" "$PANEL_CONF" || true
        fi
    fi
}


lxqt_setup_shortcuts_and_menus() {
    log "4/8: Přidávám klávesové zkratky a vlastní kontextová menu..."
    
    local SHORTCUTS_SRC="$CONTENTS_DIR/lxqt/config/shortcuts.conf"
    local SHORTCUTS_CONF="$USER_HOME/.config/lxqt/globalkeyshortcuts.conf"
    
    if [ -f "$SHORTCUTS_SRC" ]; then
        # Pojistka: Vytvoříme složku a prázdný soubor, pokud ještě neexistuje
        mkdir -p "$(dirname "$SHORTCUTS_CONF")"
        touch "$SHORTCUTS_CONF"
        
        while IFS='|' read -r label shortcut cmd || [[ -n "$label" ]]; do
            [[ "$label" =~ ^#.*$ || -z "$label" ]] && continue
            safe_shortcut="${shortcut//+/%2B}"
            
            # UNIVERZÁLNÍ NAHRAZOVÁNÍ SCRIPTŮ: 
            # Najde cokoliv, co končí na .sh nebo .py a vloží před to cestu ~/.local/bin/
            FINAL_CMD=$(echo "$cmd" | sed -E "s@([a-zA-Z0-9_-]+\.(sh|py))@$USER_HOME/.local/bin/\1@g")
            
            # BRUTÁLNÍ VRAŽDA SYSTÉMOVÉ ZKRATKY (aby LXQt nemazalo Alberta atd.)
            sed -i "/^\[${safe_shortcut}\]/,+3d" "$SHORTCUTS_CONF" 2>/dev/null || true
            sed -i "/^\[${safe_shortcut}\.99\]/,+3d" "$SHORTCUTS_CONF" 2>/dev/null || true
            
            # Zápis čisté zkratky
            echo -e "\n[${safe_shortcut}]\nComment=$label\nEnabled=true\nExec=$FINAL_CMD" >> "$SHORTCUTS_CONF"
        done < "$SHORTCUTS_SRC"

        # Super_L oprava
        sed -i '/^\[Super_L\]/,+3d' "$SHORTCUTS_CONF" 2>/dev/null || true
        echo -e "\n[Super_L]\nComment=Otevrit menu\nEnabled=true\npath=/panel/fancymenu/show_hide" >> "$SHORTCUTS_CONF"
    fi

    # Kontextové menu
    local CONTEXT_CONF="$CONTENTS_DIR/lxqt/config/contextmenu.conf"
    local ACTION_DIR="$USER_HOME/.local/share/file-manager/actions"
    if [ -s "$CONTEXT_CONF" ]; then
        mkdir -p "$ACTION_DIR"
        CURRENT_FILE=""
        while IFS= read -r line || [[ -n "$line" ]]; do
            if [[ "$line" =~ ^FILE:\ (.*\.desktop)$ ]]; then
                CURRENT_FILE="${BASH_REMATCH[1]}"
                > "$ACTION_DIR/$CURRENT_FILE"
            elif [ -n "$CURRENT_FILE" ]; then
                echo "$line" >> "$ACTION_DIR/$CURRENT_FILE"
                sed -i "s|~/.local/bin|$USER_HOME/.local/bin|g" "$ACTION_DIR/$CURRENT_FILE" || true
            fi
        done < "$CONTEXT_CONF"
    fi

    actions_config
}


lxqt_packages_install() {
        
    log "5/8 Instaluji balíčky a externí aplikace (Albert & PeaZip čistě pro amd64)..."

    # Kontrola architektury
    local SYS_ARCH=$(dpkg --print-architecture)
    if [ "$SYS_ARCH" != "amd64" ]; then
        log "UPOZORNĚNÍ: Architektura $SYS_ARCH. Tento skript instaluje externí aplikace pouze pro amd64. Přeskakuji."
        return 0
    fi

    # 1. Albert - Správná cesta pro Debian 13
    log "Nasazuji oficiální repozitář Alberta pro Debian 13..."
    
    # Zkusíme stáhnout klíč. Pokud to selže (výpadek netu), repozitář se nepřidá a APT nezkolabuje.
    if curl -fsSL --connect-timeout 10 --retry 3 https://download.opensuse.org/repositories/home:manuelschneid3r/Debian_13/Release.key | gpg --dearmor | tee /etc/apt/trusted.gpg.d/home_manuelschneid3r.gpg > /dev/null; then
        echo 'deb http://download.opensuse.org/repositories/home:/manuelschneid3r/Debian_13/ /' | tee /etc/apt/sources.list.d/albert.list
        apt-get update -y || true
        
        # Zkusíme instalaci přes apt (pro automatické updaty v budoucnu)
        if ! apt-get install -y albert; then
            log "CHYBA apt instalace. Přepínám na dynamické stažení .deb přímo z adresáře..."
            # Scraper...
            local ALBERT_BASE="https://download.opensuse.org/repositories/home:/manuelschneid3r/Debian_13/amd64/"
            local ALBERT_FILE=$(curl -s "$ALBERT_BASE" | grep -oE 'albert_[^"]+_amd64\.deb' | head -n 1)
            
            if [ -n "$ALBERT_FILE" ]; then
                log "Našel jsem balíček: $ALBERT_FILE. Stahuji..."
                wget -qO "/tmp/$ALBERT_FILE" "${ALBERT_BASE}${ALBERT_FILE}"
                dpkg -i "/tmp/$ALBERT_FILE" || apt-get install -f -y
                rm -f "/tmp/$ALBERT_FILE"
            else
                log "FATÁLNÍ CHYBA: Na té adrese se nepodařilo najít žádný albert...amd64.deb!"
            fi
        fi
    else
        log "CHYBA: Nepodařilo se stáhnout GPG klíč pro Albert (asi výpadek sítě). Přeskakuji!"
    fi

   # 2. PeaZip - Dynamické stažení nejnovější Qt6 verze z GitHubu
    log "Stahuji nejnovější PeaZip..."
    
    # Přísný filtr: musí to obsahovat "browser_download_url", "LINUX.Qt6" a "amd64.deb"
    local PEAZIP_URL=$(curl -s https://api.github.com/repos/peazip/PeaZip/releases/latest | grep "browser_download_url" | grep "LINUX.Qt6" | grep "amd64.deb" | cut -d '"' -f 4 | head -n 1)
    
    if [ -n "$PEAZIP_URL" ]; then
        log "Našel jsem odkaz: $PEAZIP_URL"
        wget -qO /tmp/peazip_latest.deb "$PEAZIP_URL"
        dpkg -i /tmp/peazip_latest.deb || apt-get install -f -y
        rm -f /tmp/peazip_latest.deb

        # --- KASTRACE PEAZIPU ---
        # Zabráníme PeaZipu, aby se do systému hlásil jako otvírák na .exe soubory
        PEAZIP_DESKTOP="/usr/share/applications/peazip.desktop"
        
        if [ -f "$PEAZIP_DESKTOP" ]; then
            log "Odstraňuji asociaci .exe z PeaZipu u zdroje..."
            sed -i 's/application\/x-ms-dos-executable;//g' "$PEAZIP_DESKTOP"
            sed -i 's/application\/x-msdownload;//g' "$PEAZIP_DESKTOP"
            sed -i 's/application\/exe;//g' "$PEAZIP_DESKTOP"
        fi
    else
        log "CHYBA: Nepodařilo se získat odkaz na PeaZip z GitHubu."
    fi
}


lxqt_config_backup() {
    log "ZÁLOHA A AUTOMATICKÁ OBNOVA (100% TAR Snapshot)"
    log "8/8 Vytvářím 1:1 TAR snapshot .config pro případ, že by si uživatel smazal .config z domovského adresáře..."
    
    # 0. Nasazení kanárka (tajný soubor)
    touch "$USER_HOME/.config/lxqt/.dapeos_ok"
    
    # 1. Čistá záloha do archivu (Zaručí zachování struktury a zamezí slučování zmetků)
    mkdir -p /opt/dapeos-backup
    tar -czf /opt/dapeos-backup/config.tar.gz -C "$USER_HOME" .config
    
    # Zabezpečíme, aby si to uživatel mohl po přihlášení sám rozbalit
    chmod 644 /opt/dapeos-backup/config.tar.gz
    
    # 2. Záchranný skript (Běží při KAŽDÉM přihlášení)
    local RESTORE_SCRIPT="/etc/X11/Xsession.d/90dapeos-restore"
    
    echo '# Kontrola na základě chybějícího kanárka' > "$RESTORE_SCRIPT"
    echo 'if [ ! -f "$HOME/.config/lxqt/.dapeos_ok" ]; then' >> "$RESTORE_SCRIPT"
    echo '    # 1. Nemilosrdně smazat zmetka, kterého LXQt vytvořilo při odhlášení' >> "$RESTORE_SCRIPT"
    echo '    rm -rf "$HOME/.config/lxqt"' >> "$RESTORE_SCRIPT"
    echo '    # 2. Rozbalit čistý 1:1 snapshot přesně tak, jak byl nastaven při instalaci' >> "$RESTORE_SCRIPT"
    echo '    tar -xzf /opt/dapeos-backup/config.tar.gz -C "$HOME"' >> "$RESTORE_SCRIPT"
    echo 'fi' >> "$RESTORE_SCRIPT"
    
    chmod 644 "$RESTORE_SCRIPT"
    -------------------------------------------------------------
}


lxqt_drive_automount() {
    log "7/8: Konfiguruji automatické a trvalé připojení interních datových disků (FSTAB)..."
    
    # Pojistka pro základní media adresář uživatele
    mkdir -p "/media/$REAL_USER" 
    chmod 755 "/media/$REAL_USER"

    # lsblk -P vypíše data ve formátu KEY="value", což je perfektní pro bezpečné parsování
    lsblk -P -o UUID,LABEL,FSTYPE,MOUNTPOINT,TYPE,RM | while read -r line; do
        
        # Nahraje hodnoty (UUID, LABEL, FSTYPE, MOUNTPOINT, TYPE, RM) do proměnných pro tento průběh cyklu
        eval "$line"
        
        # FILTRY PRO DETEKCI SPRÁVNÉHO DISKU:
        # 1. TYPE="part" -> Musí to být diskový oddíl (ne celá sda struktura)
        # 2. RM="0" -> Nesmí to být "Removable" (ignoruje to USB flashky a tvoje instalační USB)
        # 3. FSTYPE!="" a FSTYPE!="swap" -> Musí to mít souborový systém a nesmí to být swap
        # 4. MOUNTPOINT!="/" a MOUNTPOINT!="/boot*" -> Ignoruje to právě běžící systémové oddíly Debianu
        if [ "$TYPE" == "part" ] && [ "$RM" == "0" ] && [ -n "$FSTYPE" ] && [ "$FSTYPE" != "swap" ] && [ "$MOUNTPOINT" != "/" ] && [[ "$MOUNTPOINT" != /boot* ]]; then
            
            # Ošetření: Pokud disk nemá jméno (Label), vytvoříme mu hezké jméno z kousku UUID
            if [ -z "$LABEL" ]; then
                LABEL="DISK_${UUID:0:8}"
            fi

            # Definice cesty, která nesmí zmizet (fix pro cestující ikony)
            local MOUNT_DIR="/media/$REAL_USER/$LABEL"

            log "-> Detekován interní datový disk: $LABEL (UUID: $UUID)"

            # 1. Vytvoření absolutně trvalé složky
            mkdir -p "$MOUNT_DIR"
            chmod 777 "$MOUNT_DIR"

            # 2. Zápis do FSTAB (pokud tam tohle UUID ještě není zapsané)
            if ! grep -q "$UUID" /etc/fstab; then
                # x-gvfs-show zajistí, že se disk hezky ukáže v bočním panelu PCManFM-Qt
                echo "UUID=$UUID  $MOUNT_DIR  auto  nosuid,nodev,nofail,x-gvfs-show  0  0" >> /etc/fstab
                log "   [OK] Zapsáno do FSTAB. Disk se připojí automaticky."
            else
                log "   [-] Tento disk už ve FSTAB je, přeskakuji zápis."
            fi
        fi
    done
}


configure_lxqt() {
    log "=== ZAHAJUJI KOMPLEXNÍ KONFIGURACI LXQT ==="
    
    lxqt_prepare_base_configs
    lxqt_setup_system_integrations
    lxqt_setup_appearance
    lxqt_setup_shortcuts_and_menus
    lxqt_packages_install
    lxqt_setup_apps_and_defaults
    lxqt_drive_automount
    
    chown -R "$REAL_USER:$REAL_USER" "$USER_HOME/.config" "$USER_HOME/.local" || true

    # lxqt_config_backup

    sudo apt remove -y pcmanfm-qt
    
    log "=== KONFIGURACE LXQT BYLA ÚSPĚŠNĚ DOKONČENA ==="
}

