#!/bin/bash
# Read-only-ish audit of DapeOS icon/panel theming. Restores original modes.
set -u
OUT="/tmp/dapeos-icon-audit"
rm -rf "$OUT"; mkdir -p "$OUT"

sys_theme="$(xfconf-query -c xsettings -p /Net/ThemeName 2>/dev/null || true)"
panel_prop=""
for p in $(xfconf-query -c xfce4-panel -l 2>/dev/null | grep '/dark-mode$'); do
    case "$p" in /panels/panel-*/*) panel_prop="$p" ;; esac
done
[ -n "$panel_prop" ] || panel_prop="/panels/dark-mode"
panel_mode="$(xfconf-query -c xfce4-panel -p "$panel_prop" 2>/dev/null || true)"

snap() {
    local label="$1"
    {
        echo "===== $label ====="
        echo "time=$(date '+%F %T')"
        echo "Net/ThemeName=$(xfconf-query -c xsettings -p /Net/ThemeName 2>/dev/null || true)"
        echo "Net/IconThemeName=$(xfconf-query -c xsettings -p /Net/IconThemeName 2>/dev/null || true)"
        echo "ApplicationPreferDarkTheme=$(xfconf-query -c xsettings -p /Gtk/ApplicationPreferDarkTheme 2>/dev/null || true)"
        echo "all dark-mode:"
        for p in $(xfconf-query -c xfce4-panel -l 2>/dev/null | grep '/dark-mode$'); do
            echo "  $p=$(xfconf-query -c xfce4-panel -p "$p" 2>/dev/null || true)"
        done
        echo "DapeOS symlink: $(readlink -f "$HOME/.local/share/icons/DapeOS" 2>/dev/null || echo missing)"
        echo "DapeOS-Panel symlink: $(readlink -f "$HOME/.local/share/icons/DapeOS-Panel" 2>/dev/null || echo missing)"
        echo "panel processes:"
        ps -eo pid,args | grep '[x]fce4-panel' || true
        for pid in $(pgrep -f '[x]fce4-panel' 2>/dev/null); do
            echo "--- env $pid ---"
            tr '\0' '\n' <"/proc/$pid/environ" 2>/dev/null | grep -E 'GTK_THEME|PANEL_ICON|PANEL_ICONS_FORCE' || true
        done
        echo "processes:"
        pgrep -af 'dapeos-panel-watch|dapeos-theme-sync|dapeos-icon-sync|dapeos-panel-icon-sync' || true
    } >>"$OUT/state.log"
}

{
    echo "===== FILES ====="
    for f in /usr/local/bin/dapeos-theme-sync /usr/local/bin/dapeos-icon-sync \
             /usr/local/bin/dapeos-panel-watch /usr/local/bin/dapeos-panel-restart \
             /usr/local/bin/dapeos-system-icon-switch /usr/local/bin/dapeos-panel-icon-sync \
             /usr/bin/xfce4-panel /usr/bin/xfce4-panel.orig /usr/bin/xfce4-panel.bin \
             /usr/bin/xfce4-panel.real /usr/bin/xfce4-panel.realbin /usr/bin/xfce4-panel.actual; do
        [ -e "$f" ] || { echo "$f MISSING"; continue; }
        echo "--- $f ---"
        sha256sum "$f"
        if [ -L "$f" ]; then readlink -f "$f"; else head -n 8 "$f"; fi
    done
    echo "===== THEMES ====="
    for d in /usr/share/icons/Papirus /usr/share/icons/Papirus-Dark /usr/share/icons/Papirus-Light \
             /usr/share/icons/Papirus-Panel /usr/share/icons/Papirus-Panel-Light \
             /usr/share/icons/DapeOS /usr/share/icons/DapeOS-Panel; do
        echo "--- $d ---"
        [ -d "$d" ] || { echo missing; continue; }
        grep -E '^(Name|Comment|Inherits|Hidden|Directories)=' "$d/index.theme" 2>/dev/null | head -8
    done
} >"$OUT/files.log"

xfconf-query -c xsettings -m >"$OUT/xsettings-events.log" 2>&1 &
m1=$!
xfconf-query -c xfce4-panel -m >"$OUT/panel-events.log" 2>&1 &
m2=$!

snap "BASELINE"
xfconf-query -c xsettings -p /Net/ThemeName -s Adwaita:dark 2>/dev/null || true
sleep 2; snap "SYSTEM DARK"
xfconf-query -c xsettings -p /Net/ThemeName -s Adwaita:light 2>/dev/null || true
sleep 2; snap "SYSTEM LIGHT"
xfconf-query -c xfce4-panel -p "$panel_prop" -t bool -s true 2>/dev/null || true
sleep 2; snap "PANEL TRUE"
xfconf-query -c xfce4-panel -p "$panel_prop" -t bool -s false 2>/dev/null || true
sleep 2; snap "PANEL FALSE"

kill "$m1" "$m2" 2>/dev/null || true
[ -n "$sys_theme" ] && xfconf-query -c xsettings -p /Net/ThemeName -s "$sys_theme" 2>/dev/null || true
[ -n "$panel_mode" ] && xfconf-query -c xfce4-panel -p "$panel_prop" -t bool -s "$panel_mode" 2>/dev/null || true

cp -f /tmp/dapeos-panel-wrapper.log "$OUT/" 2>/dev/null || true
cp -f /tmp/dapeos-panel-icons.log "$OUT/" 2>/dev/null || true
cp -f /tmp/dapeos-panel-watch.log "$OUT/" 2>/dev/null || true

echo "AUDIT: $OUT"
echo "--- SUMMARY ---"
grep -E '^=====|Net/ThemeName=|Net/IconThemeName=|all dark-mode:|/panels/.*dark-mode=|DapeOS symlink|DapeOS-Panel symlink|panel processes|PANEL_ICON|GTK_THEME' "$OUT/state.log" | tail -100
