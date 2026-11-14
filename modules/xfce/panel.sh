#!/bin/bash
# shellcheck shell=bash
# Panel: ikony, téma, wrappery.

xfce_browser_launcher() {
    local bin icon name
    case "$BROWSER_CHOICE" in
        1) bin="google-chrome-stable"; icon="google-chrome"; name="Google Chrome" ;;
        2) bin="chromium"; icon="chromium"; name="Chromium" ;;
        3) bin="brave-browser"; icon="brave-browser"; name="Brave" ;;
        4) bin="firefox-esr"; icon="firefox-esr"; name="Firefox" ;;
        *) return 0 ;;
    esac
    command -v "$bin" >/dev/null 2>&1 || return 0

    local apps="$USER_HOME/.local/share/applications"
    local launcher="$USER_HOME/.config/xfce4/panel/launcher-13"
    install -d -m 755 "$apps" "$launcher"
    cat > "$apps/dapeos-browser.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=$name
Exec=$bin %U
Icon=$icon
Terminal=false
Categories=Network;WebBrowser;
StartupNotify=true
EOF
    cp "$apps/dapeos-browser.desktop" "$launcher/dapeos-browser.desktop"
    chown -R "$REAL_USER:$REAL_USER" "$apps/dapeos-browser.desktop" "$launcher" 2>/dev/null || true

    local xml="$USER_HOME/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml"
    [ -f "$xml" ] || return 0
    python3 - "$xml" <<'PY'
import re
import sys

path = sys.argv[1]
data = open(path, encoding="utf-8").read()
if 'name="plugin-13"' in data:
    sys.exit(0)

m3 = re.search(r'(<property name="plugin-3" type="string" value="launcher">.*?</property>)',
               data, re.S)
if m3:
    cleaned = re.sub(r'\s*<value type="string" value="dapeos-browser.desktop"/>', '',
                     m3.group(1))
    data = data.replace(m3.group(1), cleaned, 1)
    m3 = re.search(r'(<property name="plugin-3" type="string" value="launcher">.*?</property>)',
                   data, re.S)

block = ('    <property name="plugin-13" type="string" value="launcher">\n'
         '      <property name="items" type="array">\n'
         '        <value type="string" value="dapeos-browser.desktop"/>\n'
         '      </property>\n'
         '    </property>\n')
if m3:
    data = data.replace(m3.group(1), m3.group(1) + "\n" + block, 1)
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

}

