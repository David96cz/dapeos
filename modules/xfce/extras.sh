#!/bin/bash
# shellcheck shell=bash
# Doplňky: Albert, správce aktualizací, uvítací okno.

albert_setup() {
    log "Instaluji a konfiguruji Albert..."

    # --- 1) instalace: balíček (amd64) nebo přiložená binárka (ARM64) ---
    if apt-cache policy albert 2>/dev/null | grep -q 'Candidate: [0-9]'; then
        log "Používám balíček albert z repozitáře."
        DEBIAN_FRONTEND=noninteractive apt-get install -y albert \
            || log "VAROVÁNÍ: instalace balíčku albert selhala."
    else
        local SRC="$CONTENTS_DIR/xfce/albert"

        if [ "$(uname -m)" != "aarch64" ]; then
            log "UPOZORNĚNÍ: albert není v aptu a přiložená binárka je jen pro ARM64."
        elif [ ! -x "$SRC/bin/albert" ]; then
            log "UPOZORNĚNÍ: $SRC/bin/albert nenalezeno – přeskakuji."
        else
            install -d -m 755 /usr/local/bin /usr/local/lib/albert
            install -m 755 -o root -g root "$SRC/bin/albert" /usr/local/bin/albert

            if [ -d "$SRC/lib/albert" ]; then
                cp -a "$SRC/lib/albert/." /usr/local/lib/albert/
                chown -R root:root /usr/local/lib/albert
                find /usr/local/lib/albert -type f -name '*.so*' -exec chmod 755 {} +
            fi

            # cesta pro dynamický linker + obnova cache
            printf '/usr/local/lib/albert\n' > /etc/ld.so.conf.d/albert.conf
            /sbin/ldconfig 2>/dev/null || ldconfig

            if ldd /usr/local/bin/albert 2>/dev/null | grep -q 'not found'; then
                log "VAROVÁNÍ: Albertu chybí knihovny:"
                ldd /usr/local/bin/albert 2>/dev/null | grep 'not found' | while read -r l; do
                    log "  $l"
                done
            fi
        fi
    fi

    # --- 2) Albert nemá být v menu Start ---
    rm -f /usr/share/applications/albert.desktop
    rm -f "$USER_HOME/.local/share/applications/albert.desktop"
    update-desktop-database /usr/share/applications 2>/dev/null || true

    # --- 3) konfigurace ---
    local ALBERT_SRC="$CONTENTS_DIR/lxqt/config/albert.conf"
    local ALBERT_DEST="$USER_HOME/.config/albert/config"

    if [ -f "$ALBERT_SRC" ]; then
        install -d -m 755 "$(dirname "$ALBERT_DEST")"
        install -m 600 "$ALBERT_SRC" "$ALBERT_DEST"
        sed -i "s|/home/david|$USER_HOME|g" "$ALBERT_DEST"
        sed -i "s|home\\\\david|home\\\\$REAL_USER|g" "$ALBERT_DEST"
        chown "$REAL_USER:$REAL_USER" "$ALBERT_DEST"
    else
        log "UPOZORNĚNÍ: $ALBERT_SRC nenalezeno."
    fi

    # --- 4) disky pro Alberta ---
    local ALBERT_DISKS="$USER_HOME/.local/share/albert_disks"
    install -d -m 755 "$ALBERT_DISKS"
    ln -sfn /media "$ALBERT_DISKS/media"
    ln -sfn /mnt   "$ALBERT_DISKS/mnt"
    chown -R "$REAL_USER:$REAL_USER" "$ALBERT_DISKS" 2>/dev/null || true

    # --- 5) potlačení first-run / version-change hlášky ---
    local ALBERT_STATE_DIR="$USER_HOME/.local/share/albert"
    install -d -m 700 "$ALBERT_STATE_DIR"

    local AV=""
    AV="$(su - "$REAL_USER" -c 'albert --version 2>/dev/null' | awk '{print $NF}')"
    [ -n "$AV" ] || AV="35.0.0"

    printf '[General]\nlast_used_version=%s\n' "$AV" > "$ALBERT_STATE_DIR/state"
    chown -R "$REAL_USER:$REAL_USER" "$ALBERT_STATE_DIR"
}


update_manager_setup() {
    log "Nasazuji správce aktualizací (dapeos-update)..."

    local HELPER_SRC="$CONTENTS_DIR/xfce/scripts/dapeos-update-helper"
    local POLICY_SRC="$CONTENTS_DIR/xfce/config/polkit/cz.dapeos.update.policy"
    local RULES_SRC="$CONTENTS_DIR/xfce/config/polkit/49-dapeos-update.rules"
    local DESKTOP_SRC="$CONTENTS_DIR/xfce/config/dapeos-update.desktop"

    # závislosti
    DEBIAN_FRONTEND=noninteractive apt-get install -y python3-pyqt5 pkexec 2>/dev/null \
        || DEBIAN_FRONTEND=noninteractive apt-get install -y python3-pyqt5 policykit-1

    if [ -f "$HELPER_SRC" ]; then
        install -d -m 755 /usr/local/lib/dapeos
        install -m 755 -o root -g root "$HELPER_SRC" /usr/local/lib/dapeos/dapeos-update-helper
    else
        log "UPOZORNĚNÍ: $HELPER_SRC nenalezeno."
    fi

    if [ -f "$POLICY_SRC" ]; then
        install -d -m 755 /usr/share/polkit-1/actions
        install -m 644 -o root -g root "$POLICY_SRC" /usr/share/polkit-1/actions/
    fi
    if [ -f "$RULES_SRC" ]; then
        install -d -m 755 /etc/polkit-1/rules.d
        install -m 644 -o root -g root "$RULES_SRC" /etc/polkit-1/rules.d/
    fi
    if [ -f "$DESKTOP_SRC" ]; then
        install -m 644 -o root -g root "$DESKTOP_SRC" /usr/share/applications/
        update-desktop-database /usr/share/applications 2>/dev/null || true
    fi

    log "Správce aktualizací nainstalován."
}


welcome_setup() {
    log "Nasazuji uvítací okno (dapeos-welcome)..."

    local LOGO_SRC="$CONTENTS_DIR/xfce/icons/dapeos-logo.svg"
    local DESKTOP_SRC="$CONTENTS_DIR/xfce/config/dapeos-welcome.desktop"

    if [ -f "$LOGO_SRC" ]; then
        install -d -m 755 /usr/share/icons/hicolor/scalable/apps
        install -m 644 -o root -g root "$LOGO_SRC" \
            /usr/share/icons/hicolor/scalable/apps/dapeos-logo.svg
        gtk-update-icon-cache -f -t /usr/share/icons/hicolor 2>/dev/null || true
    fi

    if [ -f "$DESKTOP_SRC" ]; then
        install -m 644 -o root -g root "$DESKTOP_SRC" /usr/share/applications/
        update-desktop-database /usr/share/applications 2>/dev/null || true
    fi

}

