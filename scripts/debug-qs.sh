#!/bin/bash
set -u
cd "$(dirname "$0")/.."

# Ukliď všechny běžící quick settings (i staré instance)
for pid in $(pgrep -f '[d]apeos-quicksettings' 2>/dev/null); do
    kill -9 "$pid" 2>/dev/null || true
done
sleep 0.2

# Debug binárka
gcc -g -O0 -o /tmp/dapeos-qs-debug \
  packages/dapeos-quicksettings-c/src/dapeos-quicksettings.c \
  $(pkg-config --cflags gtk+-3.0 gio-2.0) \
  $(pkg-config --libs gtk+-3.0 gio-2.0) -lm || exit 1

CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/dapeos"
mkdir -p "$CACHE"
: > "$CACHE/qs-page"

# Po 1 s vyvolej požadavek na WiFi stránku
( sleep 1; printf 'wifi' > "$CACHE/qs-page" ) &

# GDB batch: zachyť activate, consume_page_request, on_net_open
timeout 12s gdb -q -batch \
  -ex 'break activate' \
  -ex 'break consume_page_request' \
  -ex 'break on_net_open' \
  -ex 'run' \
  -ex 'echo === STOP 1 ===\n' -ex 'bt' -ex 'continue' \
  -ex 'echo === STOP 2 ===\n' -ex 'bt' -ex 'continue' \
  -ex 'echo === STOP 3 ===\n' -ex 'bt' -ex 'continue' \
  --args /tmp/dapeos-qs-debug 2>&1 | tee /tmp/qs-debug.log

for pid in $(pgrep -f '[d]apeos-qs-debug' 2>/dev/null); do
    kill -9 "$pid" 2>/dev/null || true
done
echo
echo "Log: /tmp/qs-debug.log"
