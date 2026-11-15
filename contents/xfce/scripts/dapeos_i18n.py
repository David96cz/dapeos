"""DapeOS gettext helper for Python/PyQt apps."""
import gettext as _gettext
import os

_domain = "dapeos"
_localedir = "/usr/share/locale"
try:
    _trans = _gettext.translation(_domain, localedir=_localedir, fallback=True)
    _ = _trans.gettext
except Exception:  # noqa: BLE001
    _ = lambda s: s
