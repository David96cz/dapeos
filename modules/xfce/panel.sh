#!/bin/bash
# shellcheck shell=bash
# Panel: ikony, téma, wrappery.

xfce_panel_icons() {
    log "Nasazuji panelové ikony (DapeOS)..."

    case "$(uname -m)" in
        x86_64)  SRC_SO="$CONTENTS_DIR/xfce/bin/panel-icons-amd64.so" ;;
        aarch64) SRC_SO="$CONTENTS_DIR/xfce/bin/panel-icons-arm64.so" ;;
        *) log "nepodporovaná arch"; return 0 ;;
    esac

    install -d -m 755 /usr/local/lib/dapeos /usr/local/sbin /usr/local/share/dapeos/panel
    install -m 644 -o root -g root "$SRC_SO" /usr/local/lib/dapeos/panel-icons.so
    install -m 644 "$CONTENTS_DIR"/xfce/icons/panel/*.svg /usr/local/share/dapeos/panel/

    install -m 755 "$CONTENTS_DIR/xfce/scripts/dapeos-panel-theme" /usr/local/sbin/
    install -m 755 "$CONTENTS_DIR/xfce/scripts/dapeos-panel-theme-light" /usr/local/sbin/
    install -m 755 "$CONTENTS_DIR/xfce/scripts/dapeos-panel-watch" /usr/local/bin/

    /usr/local/sbin/dapeos-panel-theme /usr/local/share/dapeos/panel
    /usr/local/sbin/dapeos-panel-theme-light /usr/local/share/dapeos/panel

}

