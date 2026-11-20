"""Shared DapeOS Qt theme helper."""
import subprocess

from PyQt5.QtGui import QColor, QIcon, QPalette
from PyQt5.QtWidgets import QApplication


def is_dark():
    try:
        theme = subprocess.check_output(
            ["xfconf-query", "-c", "xsettings", "-p", "/Net/ThemeName"],
            text=True, timeout=3).strip()
        return "dark" in theme.lower()
    except Exception:  # noqa: BLE001
        return True


def apply_theme(app=None):
    app = app or QApplication.instance()
    app.setStyle("Fusion")
    dark = is_dark()
    QIcon.setThemeName("Papirus-Dark" if dark else "Papirus-Light")
    if not dark:
        return False
    p = QPalette()
    p.setColor(QPalette.Window, QColor("#2b2b2b"))
    p.setColor(QPalette.WindowText, QColor("#eaeaea"))
    p.setColor(QPalette.Base, QColor("#1f1f1f"))
    p.setColor(QPalette.AlternateBase, QColor("#2f2f2f"))
    p.setColor(QPalette.ToolTipBase, QColor("#2b2b2b"))
    p.setColor(QPalette.ToolTipText, QColor("#eaeaea"))
    p.setColor(QPalette.Text, QColor("#eaeaea"))
    p.setColor(QPalette.Button, QColor("#333333"))
    p.setColor(QPalette.ButtonText, QColor("#eaeaea"))
    p.setColor(QPalette.BrightText, QColor("#ff5555"))
    p.setColor(QPalette.Highlight, QColor("#2a7fca"))
    p.setColor(QPalette.HighlightedText, QColor("#ffffff"))
    p.setColor(QPalette.Disabled, QPalette.Text, QColor("#888888"))
    p.setColor(QPalette.Disabled, QPalette.ButtonText, QColor("#888888"))
    app.setPalette(p)
    return True
