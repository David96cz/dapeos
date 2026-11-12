#!/bin/bash
# shellcheck shell=bash
# Session: skel snapshot a vlastnictví souborů.

xfce_skel_snapshot() {
    log "Aktualizuji /etc/skel podle hotového profilu..."
    local d

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

    chown -R root:root /etc/skel
    chmod -R u+rwX,go+rX /etc/skel
    log "Skeleton aktualizován."
}



dapeos_session_setup() {
    log "Doplňuji session nastavení (jas, tray appleti, network-online)..."

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
    for a in nm-applet blueman blueman-applet; do
        printf '[Desktop Entry]\nType=Application\nName=%s\nHidden=true\n' "$a" \
            > "$USER_HOME/.config/autostart/$a.desktop"
        chown "$REAL_USER:$REAL_USER" "$USER_HOME/.config/autostart/$a.desktop" 2>/dev/null || true
    done

    install -d -m 755 /usr/share/dapeos
    if [ -f "$CONTENTS_DIR/xfce/config/app-names.conf" ]; then
        install -m 644 "$CONTENTS_DIR/xfce/config/app-names.conf" /usr/share/dapeos/app-names.conf
    fi

    systemctl disable NetworkManager-wait-online.service 2>/dev/null || true
}

xfce_fix_ownership() {
    chown -R "$REAL_USER:$REAL_USER" \
        "$USER_HOME/.config" "$USER_HOME/.cache" "$USER_HOME/.local" 2>/dev/null || true
}

