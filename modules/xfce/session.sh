#!/bin/bash
# shellcheck shell=bash
# Session: skel snapshot a vlastnictví souborů.

xfce_skel_snapshot() {
    log "Aktualizuji /etc/skel podle hotového profilu..."
    local d

    # Flush xfconf to disk before copying
    pkill -x xfce4-panel 2>/dev/null || true
    pkill -x xfconfd 2>/dev/null || true
    sleep 1

    for d in .config .local; do
        if [ ! -d "$USER_HOME/$d" ]; then
            log "VAROVÁNÍ: $USER_HOME/$d neexistuje, přeskakuji."
            continue
        fi

        rm -rf "/etc/skel/$d"
        mkdir -p "/etc/skel/$d"

        # "/." = včetně skrytých souborů; -a = práva, časy, symlinky
        cp -a "$USER_HOME/$d/." "/etc/skel/$d/" 2>/dev/null || true

        # co do kostry nepatří
        rm -rf "/etc/skel/$d/share/Trash" \
               "/etc/skel/$d/share/recently-used.xbel" \
               "/etc/skel/$d/lib/panel-icons.so" 2>/dev/null || true
    done

    sync
    chown -R root:root /etc/skel
    chmod -R u+rwX,go+rX /etc/skel

    if [ ! -f /etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml ]; then
        log "CHYBA: snapshot neobsahuje xfce4-panel.xml!"
    else
        log "Skeleton aktualizován (panel.xml ověřen)."
    fi
}



dapeos_session_setup() {
    log "Doplňuji session nastavení (jas, tray appleti, network-online)..."

    install -d -m 755 /usr/share/dapeos/panel-default
    install -m 644 "$CONTENTS_DIR/xfce/config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml" \
        /usr/share/dapeos/panel-default/xfce4-panel.xml
    rm -rf /usr/share/dapeos/panel-default/panel
    cp -a "$CONTENTS_DIR/xfce/config/xfce4/panel" /usr/share/dapeos/panel-default/panel 2>/dev/null || true
    chown -R root:root /usr/share/dapeos/panel-default 2>/dev/null || true

    install -d -m 755 /etc/tmpfiles.d
    : > /etc/tmpfiles.d/dapeos-backlight.conf
    local bl
    for bl in /sys/class/backlight/*; do
        [ -d "$bl" ] || continue
        printf 'f %s/brightness 0664 root video\n' "$bl" >> /etc/tmpfiles.d/dapeos-backlight.conf
    done
    systemd-tmpfiles --create /etc/tmpfiles.d/dapeos-backlight.conf 2>/dev/null || true

    install -d -m 755 "$USER_HOME/.config/autostart"
    local a
    for a in nm-applet blueman blueman-applet rustdesk xfce4-clipman-plugin-autostart xfce4-clipman; do
        printf '[Desktop Entry]\nType=Application\nName=%s\nHidden=true\n' "$a" \
            > "$USER_HOME/.config/autostart/$a.desktop"
        chown "$REAL_USER:$REAL_USER" "$USER_HOME/.config/autostart/$a.desktop" 2>/dev/null || true
    done

    if [ -f "$CONTENTS_DIR/xfce/config/xorg/40-libinput-touchpad.conf" ]; then
        install -d -m 755 /etc/X11/xorg.conf.d
        install -m 644 "$CONTENTS_DIR/xfce/config/xorg/40-libinput-touchpad.conf" \
            /etc/X11/xorg.conf.d/40-libinput-touchpad.conf
    fi

    if [ -f "$CONTENTS_DIR/xfce/config/polkit/60-rustdesk.rules" ]; then
        install -d -m 755 /etc/polkit-1/rules.d
        install -m 644 "$CONTENTS_DIR/xfce/config/polkit/60-rustdesk.rules" /etc/polkit-1/rules.d/60-rustdesk.rules
    fi
    if [ -f "$CONTENTS_DIR/xfce/config/polkit/60-dapeos-skel.rules" ]; then
        install -d -m 755 /etc/polkit-1/rules.d
        install -m 644 "$CONTENTS_DIR/xfce/config/polkit/60-dapeos-skel.rules" /etc/polkit-1/rules.d/60-dapeos-skel.rules
    fi

    if [ -f "$CONTENTS_DIR/xfce/config/apt/99dapeos-app-names" ]; then
        install -m 644 "$CONTENTS_DIR/xfce/config/apt/99dapeos-app-names" /etc/apt/apt.conf.d/99dapeos-app-names
    fi

    if [ -f "$CONTENTS_DIR/xfce/config/wireplumber/51-bluez-a2dp.conf" ]; then
        install -d -m 755 /etc/wireplumber/wireplumber.conf.d
        install -m 644 "$CONTENTS_DIR/xfce/config/wireplumber/51-bluez-a2dp.conf" \
            /etc/wireplumber/wireplumber.conf.d/51-bluez-a2dp.conf
    fi

    if [ -f "$CONTENTS_DIR/xfce/config/dapeos-settings.desktop" ]; then
        install -m 644 "$CONTENTS_DIR/xfce/config/dapeos-settings.desktop" /usr/share/applications/dapeos-settings.desktop
    fi
    if [ -f "$CONTENTS_DIR/xfce/config/dapeos-network.desktop" ]; then
        install -m 644 "$CONTENTS_DIR/xfce/config/dapeos-network.desktop" /usr/share/applications/dapeos-network.desktop
    fi
    if [ -f "$CONTENTS_DIR/xfce/config/dapeos-bluetooth.desktop" ]; then
        install -m 644 "$CONTENTS_DIR/xfce/config/dapeos-bluetooth.desktop" /usr/share/applications/dapeos-bluetooth.desktop
    fi
    if [ -f "$CONTENTS_DIR/xfce/config/dapeos-nightlight.desktop" ]; then
        rm -f "$USER_HOME/.local/share/applications/dapeos-nightlight.desktop" 2>/dev/null || true
        install -m 644 "$CONTENTS_DIR/xfce/config/dapeos-nightlight.desktop" /usr/share/applications/dapeos-nightlight.desktop
    fi

    install -d -m 755 /usr/share/dapeos
    install -d -m 755 /usr/share/locale/cs/LC_MESSAGES
    if [ -f "$CONTENTS_DIR/locale/cs/LC_MESSAGES/dapeos.mo" ]; then
        install -m 644 "$CONTENTS_DIR/locale/cs/LC_MESSAGES/dapeos.mo" \
            /usr/share/locale/cs/LC_MESSAGES/dapeos.mo
    fi
    install -m 644 "$CONTENTS_DIR/xfce/scripts/dapeos_i18n.py" /usr/local/bin/dapeos_i18n.py
    get_section "$DESKTOP_CONFIG" "SETTINGS_TO_HIDE" > /usr/share/dapeos/settings-hide.conf 2>/dev/null || true
    if [ -f "$CONTENTS_DIR/xfce/config/app-names.conf" ]; then
        install -m 644 "$CONTENTS_DIR/xfce/config/app-names.conf" /usr/share/dapeos/app-names.conf
    fi

    systemctl disable NetworkManager-wait-online.service 2>/dev/null || true
}

xfce_fix_ownership() {
    chown -R "$REAL_USER:$REAL_USER" \
        "$USER_HOME/.config" "$USER_HOME/.cache" "$USER_HOME/.local" 2>/dev/null || true
}

