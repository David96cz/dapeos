#!/bin/bash
# shellcheck shell=bash
# Systémové operace: balíčky, služby, správce přihlášení, hardware.

prepare_system() {
    log "Vypínám otravný systémový PC speaker (pípání)..."
    echo -e "blacklist pcspkr\nblacklist snd_pcsp" > /etc/modprobe.d/nobeep.conf

    mkdir -p /usr/share/backgrounds
    cp "$CONTENTS_DIR/wallpaper.png" "/usr/share/backgrounds/wallpaper.png"
    chmod 644 "/usr/share/backgrounds/wallpaper.png"

    log "Základní příprava systému..."
    
    # Záchrana Wi-Fi z instalátoru
    # local WIFI_SSID=""
    # local WIFI_PSK=""
    # if [ -f /etc/network/interfaces ]; then
    #     WIFI_SSID=$(grep 'wpa-ssid' /etc/network/interfaces | cut -d' ' -f2- | tr -d '"' | xargs)
    #     WIFI_PSK=$(grep 'wpa-psk' /etc/network/interfaces | cut -d' ' -f2- | tr -d '"' | xargs)
    # fi

    apt-get update -qq || true
    apt-get install -y sudo curl wget dpkg-dev git dbus-x11 numlockx plymouth plymouth-themes network-manager ntfs-3g
    usermod -aG sudo,audio,video,plugdev "$REAL_USER" || true

    # # Likvidace ifupdown
    # apt-get purge -y ifupdown || true
    # rm -rf /etc/network/interfaces.d/* || true
    # printf "auto lo\niface lo inet loopback\n" > /etc/network/interfaces

    # # Předání NetworkManageru
    # if [ -f /etc/NetworkManager/NetworkManager.conf ]; then
    #     sed -i 's/managed=false/managed=true/g' /etc/NetworkManager/NetworkManager.conf
    # fi
    # systemctl restart NetworkManager || true

    # # Obnovení připojení
    # sleep 3
    # if [ -n "$WIFI_SSID" ] && [ -n "$WIFI_PSK" ]; then
    #     log "Předávám Wi-Fi síť do NetworkManageru..."
    #     nmcli dev wifi connect "$WIFI_SSID" password "$WIFI_PSK" >/dev/null 2>&1 || true
    # fi

    # log "Čekám na stabilizaci sítě..."
    # for i in {1..10}; do
    #     if ping -c 1 8.8.8.8 &> /dev/null; then break; fi
    #     sleep 2
    # done

    # 2. Zakázání zabugovaného systémového ntfs3 ovladače
    echo "blacklist ntfs3" | sudo tee /etc/modprobe.d/disable-ntfs3.conf

    # 3. Propsání změn do bootovací image
    sudo update-initramfs -u
    }

# === 2. INSTALACE BALÍČKŮ A PROHLÍŽEČŮ ===

# Obal pro apt-get: opakuje a před každým novým pokusem aktualizuje indexy


apt_retry() {
    local tries=5 n=1
    while true; do
        log "apt-get $* (pokus $n/$tries)"
        if apt-get "$@"; then
            return 0
        fi
        if [ "$n" -ge "$tries" ]; then
            return 1
        fi
        log "Selhání (pravděpodobně nekonzistentní zrcadlo), za $((n*10)) s zkusím znovu s čerstvými indexy..."
        sleep $((n*10))
        apt-get update -o Acquire::http::No-Cache=true || true
        n=$((n+1))
    done
}


install_packages() {
    log "Načítám konfigurace a instaluji balíčky pro architekturu: $SYS_ARCH..."
    
    local ALL_PKGS=$(get_section "$GLOBAL_CONFIG" "INSTALL")
    ALL_PKGS+=" $(get_section "$LOCAL_CONFIG" "CORE_PACKAGES")"
    ALL_PKGS+=" $(get_section "$LOCAL_CONFIG" "EXTRA_PACKAGES")"
    
    read -r -a PKG_ARRAY <<< "$ALL_PKGS"
    
    if [ ${#PKG_ARRAY[@]} -gt 0 ]; then
        log "Aktualizuji indexy repositářů..."
        apt_retry update

        log "Opravuji případné porouchané balíčky..."
        apt_retry install -f -y || true

        log "Spouštím instalaci balíčků..."
        if ! apt_retry install -y --no-install-recommends "${PKG_ARRAY[@]}"; then
            log "CHYBA: Balíčky se nepodařilo nainstalovat ani po opakovaných pokusech."
            exit 1
        fi
        log "Instalace balíčků byla úspěšně dokončena."
    fi

    log "Instaluji prohlížeč..."
    case $BROWSER_CHOICE in
        1) 
            if command -v google-chrome &> /dev/null; then
                log "Google Chrome je již nainstalován, přeskakuji..."
            elif [ "$SYS_ARCH" == "arm64" ]; then
                log "UPOZORNĚNÍ: Google Chrome nevydává balíčky pro ARM. Instaluji jako náhradu Chromium."
                if command -v chromium &> /dev/null; then
                    log "Chromium je již nainstalováno, přeskakuji..."
                else
                    apt-get install -y chromium chromium-l10n || true
                fi
            else
                log "Stahuji Google Chrome..."
                wget --timeout=15 --tries=3 -q --show-progress -O /tmp/chrome.deb https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb && apt-get install -y /tmp/chrome.deb || log "CHYBA: Server Google neodpovídá, Chrome přeskočen." 
            fi
            ;;
        2) 
            if command -v chromium &> /dev/null; then
                log "Chromium je již nainstalováno, přeskakuji..."
            else
                apt-get install -y chromium chromium-l10n || true 
            fi
            ;;
        3) 
            if command -v brave-browser &> /dev/null; then
                log "Brave Browser je již nainstalován, přeskakuji..."
            else
                curl -fsS https://dl.brave.com/install.sh | sh || true 
            fi
            ;;
        4) 
            if command -v firefox &> /dev/null; then
                log "Firefox je již nainstalován, přeskakuji..."
            else
                apt-get install -y firefox-esr firefox-esr-l10n-cs || true 
            fi
            ;;
    esac

    log "Instaluji kancelářský balík..."
    case $OFFICE_CHOICE in
        1) 
            if command -v libreoffice &> /dev/null; then
                log "LibreOffice je již nainstalován, přeskakuji..."
            else
                apt-get install -y libreoffice libreoffice-l10n-cs || true 
            fi
            ;;
        2) 
            if command -v desktopeditors &> /dev/null; then
                log "OnlyOffice je již nainstalován, přeskakuji..."
            elif [ "$SYS_ARCH" == "arm64" ]; then
                log "Stahuji OnlyOffice (ARM64)..."
                wget --timeout=15 --tries=3 -q --show-progress -O /tmp/onlyoffice.deb https://download.onlyoffice.com/install/desktop/editors/linux/onlyoffice-desktopeditors_arm64.deb && apt-get install -y /tmp/onlyoffice.deb || true
            else
                log "Stahuji OnlyOffice (AMD64)..."
                wget --timeout=15 --tries=3 -q --show-progress -O /tmp/onlyoffice.deb https://download.onlyoffice.com/install/desktop/editors/linux/onlyoffice-desktopeditors_amd64.deb && apt-get install -y /tmp/onlyoffice.deb || true
            fi
    esac

    # -- NOVÝ BLOK PRO NEJNOVĚJŠÍ WINE (WINEHQ) A WINETRICKS --
    if [ "$WINE_REQ" == "TRUE" ]; then
        log "Zpracovávám požadavek na instalaci Wine..."
        if [ "$SYS_ARCH" == "arm64" ]; then
            log "UPOZORNĚNÍ: Architektura ARM64 nepodporuje nativní spouštění x86 Windows aplikací bez emulátoru. Instalaci Wine přeskakuji z důvodu kompatibility."
        else
            log "Povoluji 32bitovou architekturu (i386)..."
            dpkg --add-architecture i386 || true
            
            log "Přidávám oficiální WineHQ repozitář..."
            mkdir -p /etc/apt/keyrings
            wget --timeout=10 -O /etc/apt/keyrings/winehq-archive.key https://dl.winehq.org/wine-builds/winehq.key || true
            source /etc/os-release
            wget --timeout=10 -NP /etc/apt/sources.list.d/ "https://dl.winehq.org/wine-builds/debian/dists/${VERSION_CODENAME}/winehq-${VERSION_CODENAME}.sources" || true
             
            apt-get update -qq || true
            
            # PŘIDÁNO xvfb a cabextract (absolutní nutnost pro winetricks na pozadí)
            log "Instaluji nejnovější verzi WineHQ Stable..."
            apt-get install -y --install-recommends winehq-stable fonts-wine xvfb cabextract || true
            
            log "Stahuji absolutně nejnovější Winetricks..."
            wget --timeout=15 -q --show-progress -O /usr/local/bin/winetricks https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks || true
            chmod +x /usr/local/bin/winetricks || true

            log "Inicializuji Wine profil a instaluji Mono na falešném monitoru (čekejte)..."
            # Používáme xvfb-run, aby si Wine myslel, že má grafické rozhraní, jinak Mono spadne!
            su - "$REAL_USER" -c "xvfb-run -a env WINEDLLOVERRIDES=mscoree,mshtml= wineboot -u" || true
            su - "$REAL_USER" -c "xvfb-run -a winetricks -q mono" || true

            # --- SYSTÉMOVÉ POJIŠTĚNÍ WINE ---
            log "Aktivuji jádrovou podporu pro .exe a čistím cache..."
            apt install -y binfmt-support wine-binfmt icoextract icoextract-thumbnailer || true

            # Zákaz vytváření zástupců a asociací souborů pro Wine
            echo "WINEDLLOVERRIDES=\"winemenubuilder.exe=d\"" >> /etc/environment
            
            /usr/sbin/update-binfmts --enable wine || true
            systemctl restart systemd-binfmt || true
            
            su - "$REAL_USER" -c "xdg-mime default wine.desktop application/x-ms-dos-executable" || true
            su - "$REAL_USER" -c "update-desktop-database ~/.local/share/applications" || true
            
            rm -rf "$USER_HOME/.cache/thumbnails/*" || true

            log "Instaluji neprůstřelný Wine strážce (ochrana rozlišení a ikon)..."

            local WINE_WRAPPER="/usr/local/bin/wine"
            
            # 1. Záhlaví a definice cest
            echo '#!/bin/bash' > "$WINE_WRAPPER"
            echo 'CONF_FILE="$HOME/.config/pcmanfm-qt/lxqt/desktop-items.conf"' >> "$WINE_WRAPPER"
            echo '' >> "$WINE_WRAPPER"

            # 2. Záloha a ZAMKNUTÍ (Read-only), aby PCManFM-Qt nemohl ikony rozházet
            echo '# Záloha a zamknutí pozic před spuštěním' >> "$WINE_WRAPPER"
            echo 'if [ -f "$CONF_FILE" ]; then' >> "$WINE_WRAPPER"
            echo '    cp "$CONF_FILE" "${CONF_FILE}.stable"' >> "$WINE_WRAPPER"
            echo '    chmod 444 "$CONF_FILE"' >> "$WINE_WRAPPER"
            echo '    sync' >> "$WINE_WRAPPER"
            echo 'fi' >> "$WINE_WRAPPER"
            echo '' >> "$WINE_WRAPPER"

            # 3. Spuštění samotného Wine
            echo '/usr/bin/wine "$@"' >> "$WINE_WRAPPER"
            echo 'EXIT_CODE=$?' >> "$WINE_WRAPPER"
            echo '' >> "$WINE_WRAPPER"

            # 4. Návrat rozlišení monitoru
            echo 'xrandr -s 0 >/dev/null 2>&1 || true' >> "$WINE_WRAPPER"
            echo 'sleep 1' >> "$WINE_WRAPPER"
            echo '' >> "$WINE_WRAPPER"

            # 5. Obnova ikon (Tvrdý reset plochy a odemknutí souboru)
            echo 'if [ -f "${CONF_FILE}.stable" ]; then' >> "$WINE_WRAPPER"
            echo '    # Odstřelení plochy natvrdo, aby si neuložila bordel z paměti' >> "$WINE_WRAPPER"
            echo '    killall -9 pcmanfm-qt 2>/dev/null' >> "$WINE_WRAPPER"
            echo '    sleep 1' >> "$WINE_WRAPPER"
            echo '    # Odemknutí, vrácení stabilní verze a restart' >> "$WINE_WRAPPER"
            echo '    chmod 644 "$CONF_FILE"' >> "$WINE_WRAPPER"
            echo '    mv "${CONF_FILE}.stable" "$CONF_FILE"' >> "$WINE_WRAPPER"
            echo '    sync' >> "$WINE_WRAPPER"
            echo '    (pcmanfm-qt --desktop >/dev/null 2>&1 & disown)' >> "$WINE_WRAPPER"
            echo 'fi' >> "$WINE_WRAPPER"
            echo '' >> "$WINE_WRAPPER"

            echo 'exit $EXIT_CODE' >> "$WINE_WRAPPER"

            # Nastavení práv, aby byl wrapper spustitelný
            chmod +x "$WINE_WRAPPER"
        fi
    fi

    if [ "$RUSTDESK_REQ" == "TRUE" ]; then
        log "Instalace RustDesku zahájena (čistá Flatpak metoda)..."
        
        # 1. Pojistka, že je v systému nainstalovaný samotný Flatpak
        apt-get install -y flatpak
        
        # 2. Přidání oficiálního Flathub repozitáře (pokud už je, nic se nestane)
        flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
        
        # 3. Samotná instalace RustDesku (automaticky vyřeší správnou architekturu)
        flatpak install flathub com.rustdesk.RustDesk -y
        
        log "RustDesk byl úspěšně nainstalován. Žádný démon, žádné vynucování root hesel, čistý systém."
    fi
}


setup_auto_updates() {
    log "Konfiguruji profesionální automatické aktualizace..."

    # 1. Likvidace notifikátorů
    log "Odstraňuji zbytečné notifikátory..."
    apt-get purge -y plasma-discover-notifier packagekit 2>/dev/null || true

    # 2. Vypnutí standardních timerů, aby neblokovaly zámek /var/lib/dpkg/lock-frontend
    log "Deaktivuji výchozí apt timery..."
    printf 'APT::Periodic::Update-Package-Lists "0";\nAPT::Periodic::Unattended-Upgrade "0";\n' > /etc/apt/apt.conf.d/20auto-upgrades
    systemctl disable --now apt-daily.timer apt-daily-upgrade.timer 2>/dev/null || true

    # 3. Nasazení tvého skriptu
    local SRC_SCRIPT="$CONTENTS_DIR/lxqt/scripts/system-autoupdate"
    local DEST_SCRIPT="/etc/cron.daily/system-autoupdate"

    if [ -f "$SRC_SCRIPT" ]; then
        log "Instaluji autoupdate skript do cron.daily..."
        cp "$SRC_SCRIPT" "$DEST_SCRIPT"
        chmod +x "$DEST_SCRIPT"
        # Oprava vlastnictví na roota, aby cron neměl problém
        chown root:root "$DEST_SCRIPT"
    else
        log "CHYBA: Zdrojový skript nebyl nalezen v $SRC_SCRIPT!"
    fi
}

# === 3. KONFIGURACE DESKTOPOVÝCH PROSTŘEDÍ ===

# ==============================================================================
# KONFIGURACE LXQT + PODFUNKCE PRO KONFIGURACI
# ==============================================================================


setup_display_manager() {
    log "Nastavuji Display Manager (LightDM) a Autologin..."
    
    # 1. Výchozí Display Manager natvrdo na LightDM
    echo "/usr/sbin/lightdm" > /etc/X11/default-display-manager 2>/dev/null || true
    systemctl disable sddm 2>/dev/null || true
    systemctl enable lightdm 2>/dev/null || true
    dpkg-reconfigure -f noninteractive lightdm 2>/dev/null || true

    # 2. Globální nastavení LightDM (Zobrazení uživatelů a Numlock)
    local LIGHTDM_CONF="/etc/lightdm/lightdm.conf"
    if [ -f "$LIGHTDM_CONF" ]; then
        # Odkomentování a nastavení zobrazení seznamu uživatelů
        sed -i 's/^#greeter-hide-users=true/greeter-hide-users=false/' "$LIGHTDM_CONF"
        sed -i 's/^#greeter-hide-users=false/greeter-hide-users=false/' "$LIGHTDM_CONF"
        
        # Zapnutí numlocku na přihlašovací obrazovce (pokud je numlockx nainstalovaný)
        sed -i 's/^#greeter-setup-script=.*/greeter-setup-script=\/usr\/bin\/numlockx on/' "$LIGHTDM_CONF" 2>/dev/null || true
    fi

    # 3. Nastavení vzhledu podle vybraného prostředí (BEZ VYNUCENÍ RELACE)
    local GREETER_CONF="/etc/lightdm/lightdm-gtk-greeter.conf"
    mkdir -p /etc/lightdm/lightdm.conf.d
    
    # Smazání zrádných souborů, kdyby tam zbyly z předchozích pokusů
    rm -f /etc/lightdm/lightdm.conf.d/50-session.conf 2>/dev/null
    
    if [ "$DESKTOP_ENV" == "PLASMA" ]; then
        log "Aplikuji motiv Breeze pro LightDM (KDE Plasma)..."
        echo "[greeter]" > "$GREETER_CONF"
        echo "theme-name = Breeze" >> "$GREETER_CONF"
        echo "icon-theme-name = breeze" >> "$GREETER_CONF"
        echo "font-name = Noto Sans 10" >> "$GREETER_CONF"
        echo "background = /usr/share/backgrounds/wallpaper.png" >> "$GREETER_CONF"
        echo "indicators = ~host;~spacer;~clock;~spacer;~session;~power" >> "$GREETER_CONF"

        log "Nastavuji jednotnou tapetu pro KDE Lockscreen..."
        run_as_user "kwriteconfig6 --file kscreenlockerrc --group Greeter --group Wallpaper --group org.kde.image --group General --key Image \"file:///usr/share/backgrounds/wallpaper.png\" 2>/dev/null || kwriteconfig5 --file kscreenlockerrc --group Greeter --group Wallpaper --group org.kde.image --group General --key Image \"file:///usr/share/backgrounds/wallpaper.png\" 2>/dev/null"
    else
        log "Aplikuji výchozí modrý motiv pro LightDM (LXQt)..."
        echo "[greeter]" > "$GREETER_CONF"
        echo "background = /usr/share/backgrounds/wallpaper.png" >> "$GREETER_CONF"
    fi

    # 4. Nastavení Autologinu (Zápis i absolutní výmaz)
    if [ "$AUTOLOGIN_REQ" == "TRUE" ]; then
        log "Nastavuji automatické přihlášení pro uživatele $REAL_USER..."
        
        # PAM Fix (Nezbytné pro Debian)
        groupadd -r autologin 2>/dev/null || true
        gpasswd -a "$REAL_USER" autologin 2>/dev/null || true
        
        echo "[Seat:*]" > /etc/lightdm/lightdm.conf.d/autologin.conf
        echo "autologin-user=$REAL_USER" >> /etc/lightdm/lightdm.conf.d/autologin.conf
        echo "autologin-user-timeout=0" >> /etc/lightdm/lightdm.conf.d/autologin.conf
        
        # DYNAMICKÉ NALEZENÍ RELACE (Fix pro schizofrenní Plasmu)
        if [ "$DESKTOP_ENV" == "PLASMA" ]; then
            # Najde přesný název souboru (.desktop), který má Debian právě teď v sobě
            PLASMA_SESSION=$(basename $(ls /usr/share/wayland-sessions/plasma*.desktop /usr/share/xsessions/plasma*.desktop 2>/dev/null | head -n 1) .desktop)
            log "Detekována Plasma session: $PLASMA_SESSION"
            
            echo "autologin-session=$PLASMA_SESSION" >> /etc/lightdm/lightdm.conf.d/autologin.conf
        else
            echo "autologin-session=lxqt" >> /etc/lightdm/lightdm.conf.d/autologin.conf
        fi
    else
        log "Vypínám automatické přihlášení (vyžadováno heslo)..."
        
        # 1. Vyhození uživatele z PAM skupiny pro automatické přihlášení
        gpasswd -d "$REAL_USER" autologin 2>/dev/null || true
        
        # 2. Fyzické smazání konfiguračního souboru, aby to LightDM nenačetlo
        rm -f /etc/lightdm/lightdm.conf.d/autologin.conf
    fi
}



admin_security() {
    log "Aplikuji bezpečnostní profil: $SEC_PROFILE..."

    # Až tady na konci máme jistotu, že všechny balíčky (včetně cups) jsou nainstalované
    for g in sudo audio video plugdev lpadmin netdev dialout cdrom; do
        if getent group "$g" >/dev/null 2>&1; then
            usermod -aG "$g" "$REAL_USER" || true
        fi
    done

    # 1. ÚKLID: Čistý štít (odstranění zbytků, pokud skript běží opakovaně)
    rm -f "/etc/sudoers.d/99_nopasswd_$REAL_USER"
    rm -f /etc/sudoers.d/01-rootpw
    rm -f /etc/polkit-1/rules.d/49-nopasswd_global.rules

    case "$SEC_PROFILE" in
        "FAMILY")
            log "Nastavuji režim Rodinný PC (Bez hesel - Windows UAC style)..."
            
            # A) Terminál: Sudo nebude nikdy chtít heslo
            echo "$REAL_USER ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/99_nopasswd_$REAL_USER"
            chmod 0440 "/etc/sudoers.d/99_nopasswd_$REAL_USER"
            
            # B) GUI (Polkit): Zrušení vyskakovacích oken na heslo pro sudo skupinu
            mkdir -p /etc/polkit-1/rules.d/
            echo -e 'polkit.addRule(function(action, subject) {\n    if (subject.isInGroup("sudo")) {\n        return polkit.Result.YES;\n    }\n});' > /etc/polkit-1/rules.d/49-nopasswd_global.rules
            # C) Odstranění hesla pro rychlé přihlášení
            passwd -d "$REAL_USER"
            log "Systém je nyní plně odemčen. Instalace a sudo fungují bez dotazu na heslo."
            ;;

        "STANDARD")
            log "Ponechávám standardní linuxové zabezpečení..."
            # Není třeba nic nastavovat, Debian s tímto počítá v základu
            log "Sudo i přihlášení vyžadují standardní heslo uživatele."
            ;;

        "ADMIN")
            log "Nastavuji přísný režim (Sudo vyžaduje ROOT heslo)..."
            
            # Absolutní bezpečnostní pojistka (kdyby náhodou)
            if grep -q '^root:[!\*]' /etc/shadow; then
                log "CHYBA: Účet root je zamčen! Bezpečnostní pojistka vrací systém do STANDARD režimu."
            else
                # Sudo přesměrováno na heslo roota
                echo 'Defaults rootpw' > /etc/sudoers.d/01-rootpw
                chmod 0440 /etc/sudoers.d/01-rootpw
                log "Sudo nyní bezpečně vyžaduje heslo ROOT."
                
                # Umožnění vymazání hesla uživatele, pokud si to v menu zvolil
                if [ "$REMOVE_PASS" == "TRUE" ]; then
                    log "Odstraňuji heslo uživatele '$REAL_USER' pro snadné přihlášení..."
                    passwd -d "$REAL_USER"
                    log "Heslo uživatele odstraněno. Administraci kryje ROOT."
                fi
            fi
            ;;
    esac
}


hardware_detection() {
    log "Provádím detekci hardwaru pro specifické parametry jádra..."
    
    local GRUB_FILE="/etc/default/grub"
    local EXTRA_CMDLINE=""

    # 1. Detekce Bay Trail (Celeron/Pentium/Atom z této rodiny trpící na C-states zamrzání)
    if grep -iqE "(N28|N29|J19|N35|J29|Z37)[0-9][0-9]" /proc/cpuinfo 2>/dev/null; then
        log "Detekován procesor rodiny Intel Bay Trail. Přidávám opravu C-states..."
        EXTRA_CMDLINE+=" intel_idle.max_cstate=1"
    fi

    # 2. Detekce AMD Grafiky (přepnutí starých karet z radeon na amdgpu)
    if lspci -nn 2>/dev/null | grep -i vga | grep -iqE "amd|radeon"; then
        log "Detekována AMD grafika. Vynucuji moderní amdgpu ovladač pro starší karty..."
        EXTRA_CMDLINE+=" radeon.cik_support=0 amdgpu.cik_support=1 radeon.si_support=0 amdgpu.si_support=1"
    fi

    # Pokud jsme něco našli, bezpečně to zapíšeme do GRUBu
    if [ -n "$EXTRA_CMDLINE" ] && [ -f "$GRUB_FILE" ]; then
        local CURRENT_CMDLINE=$(grep "^GRUB_CMDLINE_LINUX_DEFAULT=" "$GRUB_FILE" | cut -d'"' -f2 | cut -d"'" -f2)
        
        for param in $EXTRA_CMDLINE; do
            if ! echo "$CURRENT_CMDLINE" | grep -q "$param"; then
                CURRENT_CMDLINE="$CURRENT_CMDLINE $param"
            fi
        done
        
        CURRENT_CMDLINE=$(echo "$CURRENT_CMDLINE" | xargs)
        sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"$CURRENT_CMDLINE\"|" "$GRUB_FILE" || true
        
        log "Nové parametry jádra: $CURRENT_CMDLINE"
    else
        log "Žádný specifický hardware (Bay Trail/AMD) nedetekován, parametry jádra zůstávají beze změny."
    fi
}

# ==============================================================================
# BĚH PROGRAMU (MAIN)
# ==============================================================================

