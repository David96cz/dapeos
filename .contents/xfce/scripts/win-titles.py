#!/usr/bin/env python3
import os
from Xlib import X, display

CONF = os.path.expanduser("~/.config/xfce4/xfwm4/window-titles.conf")

def expand(loc):
    """cs_CZ.UTF-8 -> [cs_cz, cs]; sr_RS@latin -> [sr_rs@latin, sr_rs, sr@latin, sr]"""
    loc = loc.split(".")[0]
    mod = ""
    if "@" in loc:
        loc, mod = loc.split("@", 1)
    lang, _, country = loc.partition("_")
    if lang in ("", "C", "POSIX"):
        return []
    out = []
    if country and mod:
        out.append(f"{lang}_{country}@{mod}")
    if country:
        out.append(f"{lang}_{country}")
    if mod:
        out.append(f"{lang}@{mod}")
    out.append(lang)
    return [x.lower() for x in out]

def system_locales():
    """Pořadí podle priority: LANGUAGE (seznam), pak LC_ALL / LC_MESSAGES / LANG."""
    raw = [x for x in os.environ.get("LANGUAGE", "").split(":") if x]
    for var in ("LC_ALL", "LC_MESSAGES", "LANG"):
        if os.environ.get(var):
            raw.append(os.environ[var])
            break
    result = []
    for r in raw:
        for c in expand(r):
            if c not in result:
                result.append(c)
    return result

LOCALES = system_locales()

def load():
    entries = {}   # třída -> {"": záložní, "cs": překlad, ...}
    cur = None
    try:
        with open(CONF, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                if line.startswith("[") and line.endswith("]"):
                    cur = line[1:-1].strip().lower()
                    entries.setdefault(cur, {})
                    continue
                if cur is None or "=" not in line:
                    continue
                k, v = line.split("=", 1)
                k, v = k.strip(), v.strip()
                if k.lower() == "name":
                    entries[cur][""] = v
                elif k.lower().startswith("name[") and k.endswith("]"):
                    entries[cur][k[5:-1].lower()] = v
    except OSError:
        pass

    titles = {}
    for cls, tr in entries.items():
        title = next((tr[l] for l in LOCALES if l in tr), tr.get(""))
        if title:
            titles[cls] = title
    return titles

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