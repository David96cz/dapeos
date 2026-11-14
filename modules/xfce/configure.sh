#!/bin/bash
# shellcheck shell=bash
# Orchestrace konfigurace XFCE.

configure_xfce() {
    log "=== ZAHAJUJI KONFIGURACI ČISTÉHO XFCE ==="
    mkdir -p "$USER_HOME/.config" "$USER_HOME/.cache" "$USER_HOME/.local"

    albert_setup
    xfce_appearance          # xfce4 konfigurace + xfce_panel_icons
    xfce_deploy_scripts      # skripty + wrappery xfce4-panel / nm-applet
    xfce_setup_apps_and_defaults
    flameshot_setup
    xfce_browser_launcher
    xfce_app_names
    xfce_actions_config
    xfce_keyboard_shortcuts
    update_manager_setup
    welcome_setup
    dapeos_session_setup
    xfce_skel_snapshot
    xfce_fix_ownership

    log "=== KONFIGURACE XFCE BYLA ÚSPĚŠNĚ DOKONČENA ==="
}

