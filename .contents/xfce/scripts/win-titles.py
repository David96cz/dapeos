#!/usr/bin/env python3
import os
from Xlib import X, display

CONF = os.path.expanduser("~/.config/xfce4/xfwm4/window-titles.conf")

def load():
    m = {}
    try:
        with open(CONF, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                k, v = line.split("=", 1)
                m[k.strip().lower()] = v.strip()
    except OSError:
        pass
    return m

titles = load()
d = display.Display()
d.set_error_handler(lambda *a: None)   # okna zanikají, chyby ignorujeme
root = d.screen().root
NET_WM_NAME = d.intern_atom("_NET_WM_NAME")
WM_NAME = d.intern_atom("WM_NAME")
WM_CLASS = d.intern_atom("WM_CLASS")
UTF8 = d.intern_atom("UTF8_STRING")

def apply(win):
    try:
        cls = win.get_wm_class()
        if not cls:
            return
        title = next((titles[c.lower()] for c in cls if c.lower() in titles), None)
        if not title:
            return
        prop = win.get_full_property(NET_WM_NAME, UTF8)
        cur = prop.value if prop else None
        if isinstance(cur, bytes):
            cur = cur.decode("utf-8", "replace")
        if cur != title:
            win.change_property(NET_WM_NAME, UTF8, 8, title.encode("utf-8"))
    except Exception:
        pass

def watch(win):
    try:
        win.change_attributes(event_mask=X.PropertyChangeMask)
        apply(win)
    except Exception:
        pass

root.change_attributes(event_mask=X.SubstructureNotifyMask)
for w in root.query_tree().children:   # už otevřená okna
    watch(w)

while True:
    ev = d.next_event()
    if ev.type == X.CreateNotify:
        watch(ev.window)
    elif ev.type == X.PropertyNotify and ev.atom in (NET_WM_NAME, WM_NAME, WM_CLASS):
        apply(ev.window)
