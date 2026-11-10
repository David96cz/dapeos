#!/bin/bash
# shellcheck shell=bash
# KDE Plasma: původní větev (konzervováno).

configure_plasma() {
    log "Aplikuji specifické nastavení pro Plasmu..."
    
    mkdir -p "$USER_HOME/.config"

    echo -e "[General]\nconfirmLogout=$CONF_OUT" > "$USER_HOME/.config/ksmserverrc" || true
    echo -e "[Wallet]\nEnabled=false" > "$USER_HOME/.config/kwalletrc" || true

    mkdir -p "$USER_HOME/.config/gtk-3.0"
    echo -e "[Settings]\ngtk-decoration-layout=icon:minimize,maximize,close" > "$USER_HOME/.config/gtk-3.0/settings.ini" || true

    #rm -f "$USER_HOME/.local/share/applications/qps.desktop" || true
    #rm -f "$USER_HOME/.local/share/applications/custom-qps.desktop" || true

    local SHORTCUTS_CONF="$USER_HOME/.config/kglobalshortcutsrc"
    touch "$SHORTCUTS_CONF"
    
    if ! grep -q "^\[qps.desktop\]" "$SHORTCUTS_CONF"; then
        echo -e "\n[qps.desktop]\n_launch=Ctrl+Shift+Esc,none,qps" >> "$SHORTCUTS_CONF"
    else
        sed -i '/^\[qps.desktop\]/,/^\[/ s/^_launch=.*/_launch=Ctrl+Shift+Esc,none,qps/' "$SHORTCUTS_CONF" || true
    fi

    if ! grep -q "^\[org.kde.spectacle.desktop\]" "$SHORTCUTS_CONF"; then
        echo -e "\n[org.kde.spectacle.desktop]\nRectangularRegionScreenShot=Meta+Shift+S,Meta+Shift+Print,Draw a rectangle to take a screenshot" >> "$SHORTCUTS_CONF"
    else
        sed -i '/^\[org.kde.spectacle.desktop\]/,/^\[/ s/^RectangularRegionScreenShot=.*/RectangularRegionScreenShot=Meta+Shift+S,Meta+Shift+Print,Draw a rectangle to take a screenshot/' "$SHORTCUTS_CONF" || true
    fi
    run_as_user "lookandfeeltool -a org.kde.plasma.twilight"
    
    local PLASMARC="$USER_HOME/.config/plasmarc"
    if [ ! -f "$PLASMARC" ]; then
        echo -e "[Theme]\nname=breeze-dark" > "$PLASMARC"
    else
        if grep -q "^\[Theme\]" "$PLASMARC"; then
            sed -i '/^\[Theme\]/,/^\[/ s/^name=.*/name=breeze-dark/' "$PLASMARC" || true
        else
            echo -e "\n[Theme]\nname=breeze-dark" >> "$PLASMARC"
        fi
    fi

    log "Odstraňuji Plasma Discover Notifier, aby neotravoval v liště..."
    apt-get purge -y plasma-discover-notifier || true

    chown -R "$REAL_USER:$REAL_USER" "$USER_HOME/.config" || true

    # Nastavení vzhledu LightDM, aby ladil s KDE Plasma (Breeze)
    log "Konfiguruji LightDM GTK Greeter pro vzhled Plasma Breeze..."

    sudo mkdir -p /etc/lightdm
    sudo bash -c 'echo "[greeter]" > /etc/lightdm/lightdm-gtk-greeter.conf'
    sudo bash -c 'echo "theme-name = Breeze" >> /etc/lightdm/lightdm-gtk-greeter.conf'
    sudo bash -c 'echo "icon-theme-name = breeze" >> /etc/lightdm/lightdm-gtk-greeter.conf'
    sudo bash -c 'echo "font-name = Noto Sans 10" >> /etc/lightdm/lightdm-gtk-greeter.conf'
    # Volitelné: Nastavení pozadí (použije výchozí Debian tapetu, pokud existuje)
    sudo bash -c 'echo "background = /usr/share/backgrounds/wallpaper.png" >> /etc/lightdm/lightdm-gtk-greeter.conf'
    # Uspořádání horní lišty: Jméno PC, mezera, hodiny, mezera, výběr relace, vypínací tlačítko
    sudo bash -c 'echo "indicators = ~host;~spacer;~clock;~spacer;~session;~power" >> /etc/lightdm/lightdm-gtk-greeter.conf'

    log "Připravuji jednorázový skript pro nastavení výchozí tapety..."
    
    local USER_BIN="/home/$REAL_USER/.local/bin"
    local AUTOSTART_DIR="/home/$REAL_USER/.config/autostart"

    sudo -u "$REAL_USER" mkdir -p "$USER_BIN" "$AUTOSTART_DIR"

    log "Aplikuji čistý fix pro LightDM a Wayland (zachování nativních relací)..."

    # 1. Vytvoření neviditelného štítu
    echo '#!/bin/bash' > /usr/local/bin/plasma-lightdm-fix.sh
    echo 'export XDG_SESSION_TYPE=wayland' >> /usr/local/bin/plasma-lightdm-fix.sh
    echo 'export XDG_SESSION_DESKTOP=KDE' >> /usr/local/bin/plasma-lightdm-fix.sh
    echo 'export XDG_CURRENT_DESKTOP=KDE' >> /usr/local/bin/plasma-lightdm-fix.sh
    echo 'unset DISPLAY' >> /usr/local/bin/plasma-lightdm-fix.sh
    echo 'unset XAUTHORITY' >> /usr/local/bin/plasma-lightdm-fix.sh
    echo 'unset DBUS_SESSION_BUS_ADDRESS' >> /usr/local/bin/plasma-lightdm-fix.sh
    echo 'exec dbus-run-session startplasma-wayland' >> /usr/local/bin/plasma-lightdm-fix.sh

    chmod +x /usr/local/bin/plasma-lightdm-fix.sh

    # 2. Únos pouze nativních Wayland relací (zachová oficiální jména i překlady)
    for desktop_file in /usr/share/wayland-sessions/plasma*.desktop; do
        if [ -f "$desktop_file" ]; then
            sed -i 's|^Exec=.*|Exec=/usr/local/bin/plasma-lightdm-fix.sh|' "$desktop_file"
        fi
    done

    # 3. Nalezení přesného jména originální relace a donucení LightDM, aby ji použil jako výchozí
    mkdir -p /etc/lightdm/lightdm.conf.d

    # Zjistí název původní relace bez .desktop (např. "plasmawayland" nebo "plasma")
    DEFAULT_SESSION=$(basename $(ls /usr/share/wayland-sessions/plasma*.desktop | head -n 1) .desktop)

    echo '[Seat:*]' > /etc/lightdm/lightdm.conf.d/50-wayland-default.conf
    echo "user-session=$DEFAULT_SESSION" >> /etc/lightdm/lightdm.conf.d/50-wayland-default.conf

    # 4. Úklid jakýchkoliv předchozích pokusů, pokud existují
    rm -f /usr/share/wayland-sessions/custom-wayland.desktop 2>/dev/null

    # 1. Tvorba kamikadze skriptu pro tapetu
    echo "#!/bin/bash" > "$USER_BIN/set-wallpaper.sh"
    
    # Pojistka: Čeká, dokud plasmashell neodpovídá na DBus
    echo "while ! dbus-send --session --dest=org.kde.plasmashell --type=method_call --print-reply /PlasmaShell org.freedesktop.DBus.Peer.Ping >/dev/null 2>&1; do" >> "$USER_BIN/set-wallpaper.sh"
    echo "    sleep 1" >> "$USER_BIN/set-wallpaper.sh"
    echo "done" >> "$USER_BIN/set-wallpaper.sh"
    echo "sleep 2" >> "$USER_BIN/set-wallpaper.sh" # Extra chvilka na dokreslení oken
    
    # Tvůj funkční dbus-send příkaz (rozšířený o panely)
    echo "dbus-send --session --dest=org.kde.plasmashell --type=method_call /PlasmaShell org.kde.PlasmaShell.evaluateScript string:\"" >> "$USER_BIN/set-wallpaper.sh"
    echo "var allDesktops = desktops();" >> "$USER_BIN/set-wallpaper.sh"
    echo "for (var i = 0; i < allDesktops.length; i++) {" >> "$USER_BIN/set-wallpaper.sh"
    echo "    var d = allDesktops[i];" >> "$USER_BIN/set-wallpaper.sh"
    echo "    d.wallpaperPlugin = 'org.kde.image';" >> "$USER_BIN/set-wallpaper.sh"
    echo "    d.currentConfigGroup = Array('Wallpaper', 'org.kde.image', 'General');" >> "$USER_BIN/set-wallpaper.sh"
    echo "    d.writeConfig('Image', 'file:///usr/share/backgrounds/wallpaper.png');" >> "$USER_BIN/set-wallpaper.sh"
    echo "}" >> "$USER_BIN/set-wallpaper.sh"
    echo "var allPanels = panels();" >> "$USER_BIN/set-wallpaper.sh"
    echo "for (var j = 0; j < allPanels.length; j++) {" >> "$USER_BIN/set-wallpaper.sh"
    echo "    allPanels[j].opacity = 'translucent';" >> "$USER_BIN/set-wallpaper.sh"
    echo "}\"" >> "$USER_BIN/set-wallpaper.sh"
    
    # SEBEVRAŽDA SKRIPTU
    echo "rm -f \"$AUTOSTART_DIR/set-wallpaper.desktop\"" >> "$USER_BIN/set-wallpaper.sh"
    echo "rm -f \"\$0\"" >> "$USER_BIN/set-wallpaper.sh"

    chmod +x "$USER_BIN/set-wallpaper.sh"

    # 2. Vytvoření spouštěče do Autostartu
    echo "[Desktop Entry]" > "$AUTOSTART_DIR/set-wallpaper.desktop"
    echo "Type=Application" >> "$AUTOSTART_DIR/set-wallpaper.desktop"
    echo "Exec=$USER_BIN/set-wallpaper.sh" >> "$AUTOSTART_DIR/set-wallpaper.desktop"
    echo "Hidden=false" >> "$AUTOSTART_DIR/set-wallpaper.desktop"
    echo "X-GNOME-Autostart-enabled=true" >> "$AUTOSTART_DIR/set-wallpaper.desktop"
    echo "Name=Auto Wallpaper Setup" >> "$AUTOSTART_DIR/set-wallpaper.desktop"

    # Sjednocení práv
    chown -R "$REAL_USER:$REAL_USER" "$USER_BIN" "$AUTOSTART_DIR"

    # ==========================================================
    # PARSOVÁNÍ CONFIGU A APLIKACE DYNAMICKÝCH PRAVIDEL
    # ==========================================================
    local PLASMA_CONF="$CONTENTS_DIR/plasma/config.txt"
    
    if [ -f "$PLASMA_CONF" ]; then
        log "Čtu dodatečnou konfiguraci z $PLASMA_CONF..."
        
        local SET_BALOO_INDEXING=$(sed -n '/^\[CONFIG\]/,/^\[/p' "$PLASMA_CONF" | grep "^SET_BALOO_INDEXING=" | cut -d= -f2 | tr -d '\r')
        local BALOO_FOLDERS=$(sed -n '/^\[CONFIG\]/,/^\[/p' "$PLASMA_CONF" | grep "^BALOO_FOLDERS=" | cut -d= -f2 | tr -d '\r' | sed "s/\$REAL_USER/$REAL_USER/g")
        local START_MENU_ICON=$(sed -n '/^\[CONFIG\]/,/^\[/p' "$PLASMA_CONF" | grep "^START_MENU_ICON=" | cut -d= -f2 | tr -d '\r')
        local REVERSE_TOUCHPAD=$(sed -n '/^\[CONFIG\]/,/^\[/p' "$PLASMA_CONF" | grep "^REVERSE_TOUCHPAD=" | cut -d= -f2 | tr -d '\r')

        # 1. NASTAVENÍ TOUCHPADU (Čistý Bash parser - 100% spolehlivost)
        log "Detekuji touchpady a generuji konfigurační skript..."
        
        local TP_SCRIPT="$USER_HOME/setup_touchpad_tmp.sh"
        echo "#!/bin/bash" > "$TP_SCRIPT"
        
        local V_DEC=""
        local P_DEC=""
        local T_NAME=""
        local IS_TOUCH=0

        # Čteme bezpečně soubor jádra řádek po řádku
        while IFS= read -r line; do
            # Prázdný řádek znamená konec jednoho zařízení
            if [ -z "$line" ]; then
                if [ "$IS_TOUCH" -eq 1 ] && [ -n "$V_DEC" ] && [ -n "$P_DEC" ] && [ -n "$T_NAME" ]; then
                    if [ "$REVERSE_TOUCHPAD" == "true" ]; then
                        echo "kwriteconfig6 --file kcminputrc --group 'Libinput' --group '$V_DEC' --group '$P_DEC' --group '$T_NAME' --key 'NaturalScroll' true 2>/dev/null || kwriteconfig5 --file kcminputrc --group 'Libinput' --group '$V_DEC' --group '$P_DEC' --group '$T_NAME' --key 'NaturalScroll' true 2>/dev/null" >> "$TP_SCRIPT"
                    fi
                    echo "kwriteconfig6 --file kcminputrc --group 'Libinput' --group '$V_DEC' --group '$P_DEC' --group '$T_NAME' --key 'ClickMethod' 2 2>/dev/null || kwriteconfig5 --file kcminputrc --group 'Libinput' --group '$V_DEC' --group '$P_DEC' --group '$T_NAME' --key 'ClickMethod' 2 2>/dev/null" >> "$TP_SCRIPT"
                    echo "kwriteconfig6 --file kcminputrc --group 'Libinput' --group '$V_DEC' --group '$P_DEC' --group '$T_NAME' --key 'TapToClick' true 2>/dev/null || kwriteconfig5 --file kcminputrc --group 'Libinput' --group '$V_DEC' --group '$P_DEC' --group '$T_NAME' --key 'TapToClick' true 2>/dev/null" >> "$TP_SCRIPT"
                fi
                # Reset proměnných pro další zařízení
                V_DEC=""; P_DEC=""; T_NAME=""; IS_TOUCH=0
                continue
            fi

            # Pokud na řádku najdeme Vendor a Product, vytáhneme je a převedeme z hex do dec
            if echo "$line" | grep -q "^I:"; then
                local v_hex=$(echo "$line" | grep -o 'Vendor=[0-9a-fA-F]*' | cut -d= -f2)
                local p_hex=$(echo "$line" | grep -o 'Product=[0-9a-fA-F]*' | cut -d= -f2)
                [ -n "$v_hex" ] && V_DEC=$((16#$v_hex))
                [ -n "$p_hex" ] && P_DEC=$((16#$p_hex))
            
            # Pokud na řádku najdeme Name, ověříme, zda je to touchpad/trackpoint
            elif echo "$line" | grep -q "^N:"; then
                T_NAME=$(echo "$line" | grep -o 'Name="[^"]*"' | cut -d'"' -f2)
                if echo "$T_NAME" | grep -iqE "touch|track|synaptics|alps|elan|focal|i2c hid"; then
                    IS_TOUCH=1
                fi
            fi
        done < /proc/bus/input/devices

        # Pojistka: Kdyby poslední zařízení v souboru nekončilo prázdným řádkem
        if [ "$IS_TOUCH" -eq 1 ] && [ -n "$V_DEC" ] && [ -n "$P_DEC" ] && [ -n "$T_NAME" ]; then
            if [ "$REVERSE_TOUCHPAD" == "true" ]; then
                echo "kwriteconfig6 --file kcminputrc --group 'Libinput' --group '$V_DEC' --group '$P_DEC' --group '$T_NAME' --key 'NaturalScroll' true 2>/dev/null || kwriteconfig5 --file kcminputrc --group 'Libinput' --group '$V_DEC' --group '$P_DEC' --group '$T_NAME' --key 'NaturalScroll' true 2>/dev/null" >> "$TP_SCRIPT"
            fi
            echo "kwriteconfig6 --file kcminputrc --group 'Libinput' --group '$V_DEC' --group '$P_DEC' --group '$T_NAME' --key 'ClickMethod' 2 2>/dev/null || kwriteconfig5 --file kcminputrc --group 'Libinput' --group '$V_DEC' --group '$P_DEC' --group '$T_NAME' --key 'ClickMethod' 2 2>/dev/null" >> "$TP_SCRIPT"
            echo "kwriteconfig6 --file kcminputrc --group 'Libinput' --group '$V_DEC' --group '$P_DEC' --group '$T_NAME' --key 'TapToClick' true 2>/dev/null || kwriteconfig5 --file kcminputrc --group 'Libinput' --group '$V_DEC' --group '$P_DEC' --group '$T_NAME' --key 'TapToClick' true 2>/dev/null" >> "$TP_SCRIPT"
        fi

        # Kontrola a spuštění vygenerovaného skriptu
        if grep -q "kwriteconfig" "$TP_SCRIPT"; then
            chown "$REAL_USER:$REAL_USER" "$TP_SCRIPT"
            chmod +x "$TP_SCRIPT"
            run_as_user "bash $TP_SCRIPT"
            log "Nastavení touchpadu/trackpointu úspěšně zapsáno."
        else
            log "Žádný touchpad nebyl úspěšně zpracován."
        fi
        rm -f "$TP_SCRIPT"

        # 2. NASTAVENÍ INDEXOVÁNÍ (Baloo)
        if [ "$SET_BALOO_INDEXING" == "true" ]; then
            log "Konfiguruji a aktivuji indexování souborů (Baloo)..."
            run_as_user "kwriteconfig6 --file baloofilerc --group 'Basic' --key 'Indexing-Enabled' true 2>/dev/null || kwriteconfig5 --file baloofilerc --group 'Basic' --key 'Indexing-Enabled' true 2>/dev/null"
            run_as_user "kwriteconfig6 --file baloofilerc --group 'General' --key 'folders' \"$BALOO_FOLDERS\" 2>/dev/null || kwriteconfig5 --file baloofilerc --group 'General' --key 'folders' \"$BALOO_FOLDERS\" 2>/dev/null"
            run_as_user "kwriteconfig6 --file baloofilerc --group 'General' --key 'first run' false 2>/dev/null || kwriteconfig5 --file baloofilerc --group 'General' --key 'first run' false 2>/dev/null"
            su - "$REAL_USER" -c "balooctl6 enable 2>/dev/null || balooctl enable 2>/dev/null || true"
        fi

        # 3. ZMĚNA IKONY START MENU (Zásah do systémových XML šablon)
        if [ -n "$START_MENU_ICON" ]; then
            log "Zapisuji ikonu menu natvrdo do systémových XML šablon Plasmy..."
            for plasmoid in kickoff kicker dash; do
                local XML_FILE="/usr/share/plasma/plasmoids/org.kde.plasma.$plasmoid/contents/config/main.xml"
                if [ -f "$XML_FILE" ]; then
                    sed -i "/<entry name=\"icon\"/,/<\/entry>/ s|<default>.*</default>|<default>$START_MENU_ICON</default>|" "$XML_FILE" || true
                fi
            done
        fi

        # 4. DODATEČNÉ NASTAVENÍ (Relace a Ikony na ploše)
        # ==========================================================
        local SET_EMPTY_SESSION=$(sed -n '/^\[CONFIG\]/,/^\[/p' "$PLASMA_CONF" | grep "^SET_EMPTY_SESSION=" | cut -d= -f2 | tr -d '\r')
        local SHOW_SYSTEM_ICONS=$(sed -n '/^\[CONFIG\]/,/^\[/p' "$PLASMA_CONF" | grep "^SHOW_SYSTEM_ICONS=" | cut -d= -f2 | tr -d '\r')

        # Obnovení relace - Spustit s prázdnou relací
        if [ "$SET_EMPTY_SESSION" == "true" ]; then
            log "Nastavuji spouštění systému s prázdnou relací..."
            run_as_user "kwriteconfig6 --file ksmserverrc --group General --key loginMode emptySession 2>/dev/null || kwriteconfig5 --file ksmserverrc --group General --key loginMode emptySession 2>/dev/null"
        fi

        # Zobrazení ikon na ploše (Domov a Koš)
        if [ "$SHOW_SYSTEM_ICONS" == "true" ]; then
            log "Vytvářím systémové ikony na ploše..."
            
            # Zjištění cesty k ploše (funguje pro CZ i EN lokalizaci)
            local DESKTOP_DIR=$(run_as_user "xdg-user-dir DESKTOP")
            
            if [ -n "$DESKTOP_DIR" ] && [ -d "$DESKTOP_DIR" ]; then
                # Domovská složka
                echo "[Desktop Entry]" > "$DESKTOP_DIR/Domov.desktop"
                echo "Icon=user-home" >> "$DESKTOP_DIR/Domov.desktop"
                echo "Type=Link" >> "$DESKTOP_DIR/Domov.desktop"
                echo "URL=file://$USER_HOME" >> "$DESKTOP_DIR/Domov.desktop"
                echo "Name=Home" >> "$DESKTOP_DIR/Domov.desktop"
                echo "Name[cs]=Domovská složka" >> "$DESKTOP_DIR/Domov.desktop"
                
                # Koš
                echo "[Desktop Entry]" > "$DESKTOP_DIR/Kos.desktop"
                echo "Icon=user-trash" >> "$DESKTOP_DIR/Kos.desktop"
                echo "Type=Link" >> "$DESKTOP_DIR/Kos.desktop"
                echo "URL=trash:/" >> "$DESKTOP_DIR/Kos.desktop"
                echo "Name=Trash" >> "$DESKTOP_DIR/Kos.desktop"
                echo "Name[cs]=Koš" >> "$DESKTOP_DIR/Kos.desktop"
                
                # Nastavení práv, aby byly ikony spustitelné a vlastněné uživatelem
                chown "$REAL_USER:$REAL_USER" "$DESKTOP_DIR/Domov.desktop" "$DESKTOP_DIR/Kos.desktop"
                chmod +x "$DESKTOP_DIR/Domov.desktop" "$DESKTOP_DIR/Kos.desktop"
            else
                log "CHYBA: Nepodařilo se detekovat složku plochy, ikony nebudou vytvořeny."
            fi
        fi

        # Vypnutí načítací obrazovky (Splash screen)
        local DISABLE_SPLASH=$(sed -n '/^\[CONFIG\]/,/^\[/p' "$PLASMA_CONF" | grep "^DISABLE_SPLASH_SCREEN=" | cut -d= -f2 | tr -d '\r')
        
        if [ "$DISABLE_SPLASH" == "true" ]; then
            log "Vypínám Splash Screen (VAROVÁNÍ: Plocha bude doskakovat na černé obrazovce)..."
            run_as_user "kwriteconfig6 --file ksplashrc --group KSplash --key Engine None 2>/dev/null || kwriteconfig5 --file ksplashrc --group KSplash --key Engine None 2>/dev/null"
            run_as_user "kwriteconfig6 --file ksplashrc --group KSplash --key Theme None 2>/dev/null || kwriteconfig5 --file ksplashrc --group KSplash --key Theme None 2>/dev/null"
        else
            log "Vytvářím a nasazuji VLASTNÍ Splash motiv s fixní tapetou..."
            
            local SPLASH_DIR="/home/$REAL_USER/.local/share/plasma/look-and-feel/custom.wallpaper.splash"
            sudo -u "$REAL_USER" mkdir -p "$SPLASH_DIR/contents/splash"

            # 1. Zápis metadat pro KDE
            echo "{" > "$SPLASH_DIR/metadata.json"
            echo "    \"KPlugin\": {" >> "$SPLASH_DIR/metadata.json"
            echo "        \"Id\": \"custom.wallpaper.splash\"," >> "$SPLASH_DIR/metadata.json"
            echo "        \"Name\": \"WallpaperSplash\"" >> "$SPLASH_DIR/metadata.json"
            echo "    }" >> "$SPLASH_DIR/metadata.json"
            echo "}" >> "$SPLASH_DIR/metadata.json"

            # 2. Zápis zdrojového kódu (QML), který jen ukáže obrázek
            echo "import QtQuick 2.15" > "$SPLASH_DIR/contents/splash/Splash.qml"
            echo "Rectangle {" >> "$SPLASH_DIR/contents/splash/Splash.qml"
            echo "    color: \"black\"" >> "$SPLASH_DIR/contents/splash/Splash.qml"
            echo "    Image {" >> "$SPLASH_DIR/contents/splash/Splash.qml"
            echo "        anchors.fill: parent" >> "$SPLASH_DIR/contents/splash/Splash.qml"
            echo "        source: \"file:///usr/share/backgrounds/wallpaper.png\"" >> "$SPLASH_DIR/contents/splash/Splash.qml"
            echo "        fillMode: Image.PreserveAspectCrop" >> "$SPLASH_DIR/contents/splash/Splash.qml"
            echo "    }" >> "$SPLASH_DIR/contents/splash/Splash.qml"
            echo "}" >> "$SPLASH_DIR/contents/splash/Splash.qml"

            # 3. Nastavení práv
            chown -R "$REAL_USER:$REAL_USER" "/home/$REAL_USER/.local/share/plasma"

            # 4. Aktivace našeho nového motivu
            run_as_user "kwriteconfig6 --file ksplashrc --group KSplash --key Engine KSplashQML 2>/dev/null || kwriteconfig5 --file ksplashrc --group KSplash --key Engine KSplashQML 2>/dev/null"
            run_as_user "kwriteconfig6 --file ksplashrc --group KSplash --key Theme custom.wallpaper.splash 2>/dev/null || kwriteconfig5 --file ksplashrc --group KSplash --key Theme custom.wallpaper.splash 2>/dev/null"
        fi

        # log "Nasazuji DBus fix pro zamykání Start menu přes LightDM..."
        
        # local USER_BIN="/home/$REAL_USER/.local/bin"
        # local AUTOSTART_DIR="/home/$REAL_USER/.config/autostart"

        # # Vytvoření složek pod právy uživatele
        # sudo -u "$REAL_USER" mkdir -p "$USER_BIN" "$AUTOSTART_DIR"

        # # 1. Zápis samotného skriptu (Escapujeme znaky, aby to bash sežral čistě)
        # echo "#!/bin/bash" > "$USER_BIN/lock-fix.sh"
        # echo "dbus-monitor --session \"type='signal',interface='org.freedesktop.ScreenSaver'\" | while read x; do" >> "$USER_BIN/lock-fix.sh"
        # echo "  if echo \"\$x\" | grep -q \"boolean true\"; then" >> "$USER_BIN/lock-fix.sh"
        # echo "    dm-tool lock" >> "$USER_BIN/lock-fix.sh"
        # echo "  fi" >> "$USER_BIN/lock-fix.sh"
        # echo "done" >> "$USER_BIN/lock-fix.sh"

        # # 2. Zápis autostart souboru
        # echo "[Desktop Entry]" > "$AUTOSTART_DIR/lock-fix.desktop"
        # echo "Type=Application" >> "$AUTOSTART_DIR/lock-fix.desktop"
        # echo "Exec=$USER_BIN/lock-fix.sh" >> "$AUTOSTART_DIR/lock-fix.desktop"
        # echo "Hidden=false" >> "$AUTOSTART_DIR/lock-fix.desktop"
        # echo "NoDisplay=false" >> "$AUTOSTART_DIR/lock-fix.desktop"
        # echo "X-GNOME-Autostart-enabled=true" >> "$AUTOSTART_DIR/lock-fix.desktop"
        # echo "Name=LightDM Lock Fix" >> "$AUTOSTART_DIR/lock-fix.desktop"
        # echo "Comment=Přesměrování nativního KDE zamykání na dm-tool" >> "$AUTOSTART_DIR/lock-fix.desktop"

        # # 3. Nastavení práv a vlastnictví
        # chmod +x "$USER_BIN/lock-fix.sh"
        # chown -R "$REAL_USER:$REAL_USER" "$USER_BIN" "$AUTOSTART_DIR"
    fi
}

# === 4. SYSTÉMOVÉ SLUŽBY A BOOT ===

