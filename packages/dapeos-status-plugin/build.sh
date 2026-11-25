#!/bin/bash
# Build the DapeOS event-driven status panel plugin.
set -euo pipefail
if [ "$EUID" -ne 0 ]; then exec sudo bash "$0" "$@"; fi

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ARCH="$(dpkg --print-architecture)"
MULTIARCH="$(dpkg-architecture -qDEB_HOST_MULTIARCH)"
OUT="$HERE"
BUILD="$(mktemp -d)"

apt-get install -y build-essential pkg-config \
    libgtk-3-dev libxfce4panel-2.0-dev libxfce4ui-2-dev \
    libxfce4util-dev librsvg2-dev libxfconf-0-dev

gcc -O2 -fPIC -shared \
    $(pkg-config --cflags gtk+-3.0 libxfce4panel-2.0 libxfce4util-1.0 librsvg-2.0) \
    -o "$BUILD/libdapeos-status.so" "$HERE/src/dapeos-status.c" \
    $(pkg-config --libs gtk+-3.0 libxfce4panel-2.0 libxfce4util-1.0 librsvg-2.0)

PKG="$BUILD/pkg"
mkdir -p "$PKG/DEBIAN" \
         "$PKG/usr/lib/$MULTIARCH/xfce4/panel/plugins" \
         "$PKG/usr/share/xfce4/panel/plugins"

cp "$BUILD/libdapeos-status.so" "$PKG/usr/lib/$MULTIARCH/xfce4/panel/plugins/"
cp "$HERE/dapeos-status.desktop" "$PKG/usr/share/xfce4/panel/plugins/"

cat > "$PKG/DEBIAN/control" <<CTRL
Package: dapeos-status-plugin
Version: 1.0
Architecture: $ARCH
Maintainer: DapeOS <dapeos@localhost>
Depends: libgtk-3-0t64 | libgtk-3-0, libglib2.0-0t64 | libglib2.0-0, libxfce4panel-2.0-4, librsvg2-2
Description: DapeOS event-driven panel status
 Network, battery and volume status for the XFCE panel.
CTRL

dpkg-deb --build "$PKG" "$OUT/dapeos-status-plugin_1.0_${ARCH}.deb"
rm -rf "$BUILD"
echo "Hotovo: $OUT/dapeos-status-plugin_1.0_${ARCH}.deb"
