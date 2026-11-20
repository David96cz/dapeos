"""Shared DapeOS Qt theme helper."""
import subprocess

from PyQt5.QtCore import QTimer
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
        p = QPalette()
        p.setColor(QPalette.Window, QColor("#f5f5f5"))
        p.setColor(QPalette.WindowText, QColor("#222222"))
        p.setColor(QPalette.Base, QColor("#ffffff"))
        p.setColor(QPalette.AlternateBase, QColor("#f0f0f0"))
        p.setColor(QPalette.Text, QColor("#222222"))
        p.setColor(QPalette.Button, QColor("#e0e0e0"))
        p.setColor(QPalette.ButtonText, QColor("#222222"))
        p.setColor(QPalette.Highlight, QColor("#2a7fca"))
        p.setColor(QPalette.HighlightedText, QColor("#ffffff"))
        app.setPalette(p)
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


def install_theme_watch(app=None):
    """Repaint running widgets when the GTK theme changes."""
    app = app or QApplication.instance()
    timer = QTimer(app)
    state = {"dark": is_dark()}

    def tick():
        dark = is_dark()
        if dark == state["dark"]:
            return
        state["dark"] = dark
        apply_theme(app)
        for w in app.allWidgets():
            try:
                w.style().unpolish(w)
                w.style().polish(w)
                w.update()
            except Exception:  # noqa: BLE001
                pass

    timer.timeout.connect(tick)
    timer.start(1500)
    return timer
