#!/bin/bash
set -euo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ARCH="$(dpkg --print-architecture)"
BUILD="$(mktemp -d)"
trap 'rm -rf "$BUILD"' EXIT

gcc -O2 -Wall -o "$BUILD/dapeos-quicksettings-c" "$HERE/src/dapeos-quicksettings.c" \
  $(pkg-config --cflags gtk+-3.0 gio-2.0) \
  $(pkg-config --libs gtk+-3.0 gio-2.0) -lm

PKG="$BUILD/pkg"
mkdir -p "$PKG/DEBIAN" "$PKG/usr/local/bin"
cp "$BUILD/dapeos-quicksettings-c" "$PKG/usr/local/bin/"
cat > "$PKG/DEBIAN/control" <<CTRL
Package: dapeos-quicksettings-c
Version: 1.0
Architecture: $ARCH
Maintainer: DapeOS <dapeos@localhost>
Depends: libgtk-3-0t64 | libgtk-3-0, libglib2.0-0t64 | libglib2.0-0, libpango-1.0-0t64 | libpango-1.0-0, libcairo2, libgdk-pixbuf-2.0-0t64 | libgdk-pixbuf-2.0-0
Description: DapeOS C quick settings
 Lightweight GTK quick settings for DapeOS.
CTRL
dpkg-deb --root-owner-group --build "$PKG" "$HERE/dapeos-quicksettings-c_1.0_${ARCH}.deb"
