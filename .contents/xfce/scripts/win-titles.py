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
    entries = {}   # třída -> {"names": {jazyk: název}, "replace": [texty]}
    cur = None
    try:
        with open(CONF, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                if line.startswith("[") and line.endswith("]"):
                    cur = line[1:-1].strip().lower()
                    entries.setdefault(cur, {"names": {}, "replace": []})
                    continue
                if cur is None or "=" not in line:
                    continue
                k, v = line.split("=", 1)
                k, v = k.strip(), v.strip()
                kl = k.lower()
                if kl == "name":
                    entries[cur]["names"][""] = v
                elif kl.startswith("name[") and kl.endswith("]"):
                    entries[cur]["names"][kl[5:-1]] = v
                elif kl == "replace" and v:
                    entries[cur]["replace"].append(v)
    except OSError:
        pass

    rules = {}
    for cls, e in entries.items():
        names = e["names"]
        title = next((names[l] for l in LOCALES if l in names), names.get(""))
        if title:
            rules[cls] = (title, e["replace"])
    return rules

rules = load()
d = display.Display()
d.set_error_handler(lambda *a: None)   # okna zanikají, chyby ignorujeme
root = d.screen().root
NET_WM_NAME = d.intern_atom("_NET_WM_NAME")
WM_NAME = d.intern_atom("WM_NAME")
WM_CLASS = d.intern_atom("WM_CLASS")
UTF8 = d.intern_atom("UTF8_STRING")

def target(cur, title, replaces):
    """Vrátí nový titulek, nebo None, když není co měnit."""
    if not replaces:
        return title                     # pevný titulek
    if not cur:
        return None
    for r in replaces:
        if r in cur:
            if r in title and title in cur:
                return None              # už nahrazeno (ochrana proti zacyklení)
            return cur.replace(r, title)
    return None

def apply(win):
    try:
        cls = win.get_wm_class()
        if not cls:
            return
        rule = next((rules[c.lower()] for c in cls if c.lower() in rules), None)
        if not rule:
            return
        title, replaces = rule
        prop = win.get_full_property(NET_WM_NAME, UTF8)
        cur = prop.value if prop else None
        if isinstance(cur, bytes):
            cur = cur.decode("utf-8", "replace")
        new = target(cur, title, replaces)
        if new and new != cur:
            win.change_property(NET_WM_NAME, UTF8, 8, new.encode("utf-8"))
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