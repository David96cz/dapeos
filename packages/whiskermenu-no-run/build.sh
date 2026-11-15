#!/bin/bash
# Build a patched xfce4-whiskermenu-plugin without the "Run" search action.
# Run as root on Debian trixie (native arch). Output: this directory.
set -euo pipefail

if [ "$EUID" -ne 0 ]; then
    exec sudo --preserve-env=WORK bash "$0" "$@"
fi

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd -- "$HERE/../.." && pwd)"
PATCH="$HERE/no-run.patch"
WORK="${WORK:-/tmp/dapeos-whiskermenu-build}"
ARCH="$(dpkg --print-architecture)"
OUT="$HERE"

echo "== DapeOS: build WhiskerMenu without Run action =="
echo "Architecture: $ARCH"
echo "Work: $WORK"
echo "Output: $OUT"

apt-get update
apt-get install -y --no-install-recommends \
    build-essential dpkg-dev devscripts fakeroot ca-certificates

# Ensure deb-src entries exist.
if ! grep -Rqs '^deb-src' /etc/apt/sources.list /etc/apt/sources.list.d/ 2>/dev/null; then
    cat > /etc/apt/sources.list.d/dapeos-deb-src.list <<'SRC'
deb-src http://deb.debian.org/debian trixie main contrib non-free non-free-firmware
deb-src http://deb.debian.org/debian trixie-updates main contrib non-free non-free-firmware
deb-src http://security.debian.org/debian-security trixie-security main contrib non-free non-free-firmware
SRC
    apt-get update
fi

apt-get build-dep -y xfce4-whiskermenu-plugin

rm -rf "$WORK"
mkdir -p "$WORK"
cd "$WORK"

apt-get source xfce4-whiskermenu-plugin
SRCDIR="$(find "$WORK" -maxdepth 1 -type d -name 'xfce4-whiskermenu-plugin-*' | head -n1)"
[ -n "$SRCDIR" ] || { echo "Source directory not found" >&2; exit 1; }
cd "$SRCDIR"

patch -p1 --forward < "$PATCH"

BASEVER="$(dpkg-parsechangelog -SVersion)"
NEWVER="${BASEVER}+dapeos1"
export DEBEMAIL="dapeos@localhost"
export DEBFULLNAME="DapeOS"
dch --newversion "$NEWVER" --distribution trixie \
    "Remove Run action from WhiskerMenu search results."

dpkg-buildpackage -b -uc -us -j"$(nproc)"

DEB="$(find "$WORK" -maxdepth 1 -name "xfce4-whiskermenu-plugin_${NEWVER}_${ARCH}.deb" | head -n1)"
[ -n "$DEB" ] || DEB="$(find "$WORK" -maxdepth 1 -name "xfce4-whiskermenu-plugin_*_${ARCH}.deb" | head -n1)"
[ -n "$DEB" ] || { echo "Built .deb not found" >&2; exit 1; }
cp -v "$DEB" "$OUT/"
echo
echo "Hotovo: $OUT/$(basename "$DEB")"
echo "Nainstaluj: apt-get install -y '$OUT/$(basename "$DEB")' && apt-mark hold xfce4-whiskermenu-plugin"
