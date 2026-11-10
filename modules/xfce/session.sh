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


xfce_fix_ownership() {
    chown -R "$REAL_USER:$REAL_USER" \
        "$USER_HOME/.config" "$USER_HOME/.cache" "$USER_HOME/.local" 2>/dev/null || true
}

