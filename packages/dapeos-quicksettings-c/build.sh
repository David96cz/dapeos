#!/bin/bash
set -euo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
OUT="${OUT:-$HERE/dapeos-quicksettings-c}"
gcc -O2 -Wall -o "$OUT" "$HERE/src/dapeos-quicksettings.c" \
  $(pkg-config --cflags --libs gtk+-3.0 gio-2.0 -lm)
echo "Hotovo: $OUT"
