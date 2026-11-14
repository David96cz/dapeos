#!/usr/bin/env python3
"""Vloží samostatný launcher plugin-13 pred plugin-11."""
import sys

path = sys.argv[1]
data = open(path, encoding="utf-8").read()
if 'name="plugin-13"' in data:
    sys.exit(0)

block = ('    <property name="plugin-13" type="string" value="launcher">\n'
         '      <property name="items" type="array">\n'
         '        <value type="string" value="dapeos-browser.desktop"/>\n'
         '      </property>\n'
         '    </property>\n')
anchor = '    <property name="plugin-11"'
if anchor not in data:
    sys.exit(1)
data = data.replace(anchor, block + anchor, 1)
open(path, "w", encoding="utf-8").write(data)
