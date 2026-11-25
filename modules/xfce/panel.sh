#!/bin/bash
# shellcheck shell=bash
# Panel: ikony, téma, wrappery.

whisker_rename() {
    local desc="/usr/share/xfce4/panel/plugins/whiskermenu.desktop"
    if [ -f "$desc" ]; then
        sed -i 's/^Name=.*/Name=Start Menu/' "$desc"
        if grep -q '^Name\[cs\]=' "$desc"; then
            sed -i 's/^Name\[cs\]=.*/Name[cs]=Nabídka Start/' "$desc"
        else
            sed -i '/^Name=/a Name[cs]=Nabídka Start' "$desc"
        fi
    fi

    local mo="/usr/share/locale/cs/LC_MESSAGES/xfce4-whiskermenu-plugin.mo"
    [ -f "$mo" ] || return 0
    command -v msgunfmt >/dev/null 2>&1 || return 0
    msgunfmt "$mo" -o /tmp/wm.po 2>/dev/null || return 0
    sed -i 's/msgstr "Nabídka Whisker"/msgstr "Nabídka Start"/' /tmp/wm.po
    msgfmt /tmp/wm.po -o "$mo" 2>/dev/null || true
    rm -f /tmp/wm.po
}

xfce_clock_locale() {
    local xml="$USER_HOME/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml"
    [ -f "$xml" ] || return 0
    if [ "$SYS_LANG_CODE" != "en_US" ] && [ "${DAPEOS_LANG:-}" != "en" ]; then
        return 0
    fi
    python3 - "$xml" <<'INNER'
import re
import sys
path = sys.argv[1]
data = open(path, encoding="utf-8").read()
data = re.sub(r'(<property name="digital-time-format" type="string" value=")[^"]*(")',
              r'\1%-I:%M %p\2', data)
data = re.sub(r'(<property name="digital-date-format" type="string" value=")[^"]*(")',
              r'\1 %a, %m/%d/%Y \2', data)
open(path, "w", encoding="utf-8").write(data)
INNER
}

xfce_browser_launcher() {
    local browser_id
    case "$BROWSER_CHOICE" in
        1) browser_id="google-chrome.desktop" ;;
        2) browser_id="chromium.desktop" ;;
        3) browser_id="brave-browser.desktop" ;;
        4) browser_id="firefox-esr.desktop" ;;
        *) return 0 ;;
    esac

    local launcher="$USER_HOME/.config/xfce4/panel/launcher-4"
    install -d -m 755 "$launcher"
    if [ -f "/usr/share/applications/$browser_id" ]; then
        cp "/usr/share/applications/$browser_id" "$launcher/$browser_id"
        chown "$REAL_USER:$REAL_USER" "$launcher/$browser_id" 2>/dev/null || true
    fi

    local xml="$USER_HOME/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml"
    [ -f "$xml" ] || return 0
    python3 - "$xml" "$browser_id" <<'PY'
import sys

path, browser = sys.argv[1], sys.argv[2]
data = open(path, encoding="utf-8").read()
for old in ("google-chrome.desktop", "chromium.desktop",
            "brave-browser.desktop", "firefox-esr.desktop",
            "dapeos-browser.desktop"):
    data = data.replace(f'value="{old}"', f'value="{browser}"')
open(path, "w", encoding="utf-8").write(data)
PY
}

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

    # Only DapeOS Icons remains visible in Appearance.
    for theme in Papirus Papirus-Dark Papirus-Light Papirus-Panel Papirus-Panel-Light; do
        f="/usr/share/icons/$theme/index.theme"
        [ -f "$f" ] || continue
        grep -q '^Hidden=true' "$f" || sed -i '/^\[Icon Theme\]/a Hidden=true' "$f"
    done
}

