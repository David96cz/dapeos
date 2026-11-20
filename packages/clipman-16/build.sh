#!/bin/bash
# Build xfce4-clipman-plugin with a 16px panel icon.
set -euo pipefail

if [ "$EUID" -ne 0 ]; then
    exec sudo --preserve-env=WORK bash "$0" "$@"
fi

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
WORK="${WORK:-/tmp/dapeos-clipman-build}"
ARCH="$(dpkg --print-architecture)"
OUT="$HERE"

apt-get update
apt-get install -y --no-install-recommends \
    build-essential dpkg-dev devscripts fakeroot ca-certificates

if ! grep -Rqs '^deb-src' /etc/apt/sources.list /etc/apt/sources.list.d/ 2>/dev/null; then
    cat > /etc/apt/sources.list.d/dapeos-deb-src.list <<'SRC'
deb-src http://deb.debian.org/debian trixie main contrib non-free non-free-firmware
deb-src http://deb.debian.org/debian trixie-updates main contrib non-free non-free-firmware
deb-src http://security.debian.org/debian-security trixie-security main contrib non-free non-free-firmware
SRC
    apt-get update
fi

apt-get build-dep -y xfce4-clipman-plugin

rm -rf "$WORK"
mkdir -p "$WORK"
cd "$WORK"
apt-get source xfce4-clipman-plugin
SRCDIR="$(find "$WORK" -maxdepth 1 -type d -name 'xfce4-clipman-plugin-*' | head -n1)"
[ -n "$SRCDIR" ] || { echo "Source directory not found" >&2; exit 1; }
cd "$SRCDIR"

patch -p1 --forward < "$HERE/clipman-16.patch"

BASEVER="$(dpkg-parsechangelog -SVersion)"
NEWVER="${BASEVER}+dapeos1"
export DEBEMAIL="dapeos@localhost"
export DEBFULLNAME="DapeOS"
dch --newversion "$NEWVER" --distribution trixie \
    "Use a 16px icon in the panel plugin."

dpkg-buildpackage -b -uc -us -j"$(nproc)"

DEB="$(find "$WORK" -maxdepth 1 -name "xfce4-clipman-plugin_*_${ARCH}.deb" | head -n1)"
[ -n "$DEB" ] || { echo "Built .deb not found" >&2; exit 1; }
cp -v "$DEB" "$OUT/"
echo "Hotovo: $OUT/$(basename "$DEB")"
