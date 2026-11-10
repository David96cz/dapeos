#!/bin/bash
# shellcheck shell=bash
# GRUB, Plymouth a start systému.

PLYMOUTH_MARKER="/var/lib/dapeos/plymouth.done"

plymouth_current_theme() {
    sed -n 's/^Theme=//p' /etc/plymouth/plymouthd.conf 2>/dev/null | head -1
}


plymouth_ready() {
    local want="$1" cur

    command -v plymouth-set-default-theme >/dev/null 2>&1 || return 1
    grep -qE '^GRUB_CMDLINE_LINUX_DEFAULT=.*(^|[" ])splash([ " ]|$)' /etc/default/grub || return 1

    cur="$(plymouth_current_theme)"
    [ "$cur" = "$want" ] || return 1

    [ -f "$PLYMOUTH_MARKER" ] || return 1
    [ "$(cat "$PLYMOUTH_MARKER")" = "$want" ] || return 1
}


setup_boot() {
    log "Nastavuji GRUB a Boot Logo..."

    # --- 1) základní GRUB ---
    sed -i '/^GRUB_BACKGROUND/d' /etc/default/grub
    sed -i "s/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=$TIMEOUT/" /etc/default/grub

    if grep -q '^GRUB_TIMEOUT_STYLE=' /etc/default/grub; then
        sed -i 's/^GRUB_TIMEOUT_STYLE=.*/GRUB_TIMEOUT_STYLE=hidden/' /etc/default/grub
    else
        echo 'GRUB_TIMEOUT_STYLE=hidden' >> /etc/default/grub
    fi

    sed -i 's/^#GRUB_TERMINAL=console/GRUB_TERMINAL=console/' /etc/default/grub

    # --- 2) cmdline: jeden zápis, existující parametry zůstanou ---
    local cur
    cur="$(sed -n 's/^GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"/\1/p' /etc/default/grub | head -1)"

    if [ "$BOOT_LOGO" = "TRUE" ]; then
        for p in quiet splash loglevel=3 rd.systemd.show_status=false vga=current; do
            case " $cur " in *" $p "*) ;; *) cur="${cur:+$cur }$p" ;; esac
        done
    else
        cur="$(printf '%s\n' $cur | grep -vx 'splash' | tr '\n' ' ')"
        cur="${cur% }"
        case " $cur " in *" quiet "*) ;; *) cur="${cur:+$cur }quiet" ;; esac
    fi

    sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"$cur\"|" /etc/default/grub

    # --- 3) Plymouth: jen když ještě není hotový ---
    if [ "$BOOT_LOGO" = "TRUE" ]; then
        local theme="bgrt"

        if plymouth_ready "$theme"; then
            log "Plymouth je už nastavený ($theme) – initramfs nepřegenerovávám."
        elif command -v plymouth-set-default-theme >/dev/null 2>&1; then
            log "Nastavuji Plymouth ($theme) a přegenerovávám initramfs…"
            plymouth-set-default-theme -R "$theme" 2>/dev/null \
                || plymouth-set-default-theme -R spinner 2>/dev/null || true
            install -d -m 755 "$(dirname "$PLYMOUTH_MARKER")"
            printf '%s\n' "$theme" > "$PLYMOUTH_MARKER"
        else
            log "UPOZORNĚNÍ: Plymouth není nainstalovaný, přeskakuji."
        fi
    fi

    hardware_detection
    update-grub || true
    systemctl set-default graphical.target || true
}

