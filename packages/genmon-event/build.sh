#!/bin/bash
set -euo pipefail
if [ "$EUID" -ne 0 ]; then exec sudo bash "$0" "$@"; fi
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ARCH="$(dpkg --print-architecture)"; OUT="$HERE"; BUILD=/tmp/dapeos-genmon-build
apt-get install -y build-essential dpkg-dev devscripts fakeroot
if ! grep -Rqs '^deb-src' /etc/apt/sources.list /etc/apt/sources.list.d/ 2>/dev/null; then
  cat > /etc/apt/sources.list.d/dapeos-deb-src.list <<SRC
deb-src http://deb.debian.org/debian trixie main contrib non-free non-free-firmware
SRC
  apt-get update
fi
apt-get build-dep -y xfce4-genmon-plugin
rm -rf "$BUILD"; mkdir -p "$BUILD"; cd "$BUILD"
apt-get source xfce4-genmon-plugin
SRC="$(find "$BUILD" -maxdepth 1 -type d -name 'xfce4-genmon-plugin-*' | head -1)"
cd "$SRC"
patch -p1 --forward < "$HERE/genmon-event.patch"
BASE="$(dpkg-parsechangelog -SVersion)"; export DEBEMAIL=dapeos@localhost DEBFULLNAME=DapeOS
dch --newversion "${BASE}+dapeos1" --distribution trixie "Refresh on DapeOS status trigger file."
dpkg-buildpackage -b -uc -us -j"$(nproc)"
DEB="$(find "$BUILD" -maxdepth 1 -name "xfce4-genmon-plugin_*_${ARCH}.deb" | head -1)"
[ -n "$DEB" ] || { echo "deb not found" >&2; exit 1; }
cp -v "$DEB" "$OUT/"
