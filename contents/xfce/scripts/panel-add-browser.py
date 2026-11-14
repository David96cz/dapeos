#!/usr/bin/env python3
"""Vloží prohlížeč jako plugin-4 hned za plugin-3 (Thunar)."""
import sys

path = sys.argv[1]
data = open(path, encoding="utf-8").read()

# clipman z plugin-4 na plugin-14
if 'name="plugin-4"' in data and 'name="plugin-14"' not in data:
    data = data.replace('name="plugin-4"', 'name="plugin-14"', 1)

# už existuje prohlížeč?
if 'plugin-4' in data and 'dapeos-browser.desktop' in data:
    open(path, "w", encoding="utf-8").write(data)
    sys.exit(0)

block = ('    <property name="plugin-4" type="string" value="launcher">\n'
         '      <property name="items" type="array">\n'
         '        <value type="string" value="dapeos-browser.desktop"/>\n'
         '      </property>\n'
         '    </property>\n')
anchor = '    <property name="plugin-11"'
if anchor not in data:
    sys.exit(1)
data = data.replace(anchor, block + anchor, 1)
open(path, "w", encoding="utf-8").write(data)
