#!/bin/bash
# Build Thunar without the hardcoded "File System" device entry.
# Run as root on Debian trixie (native arch). Output: this directory.
set -euo pipefail

if [ "$EUID" -ne 0 ]; then
    exec sudo --preserve-env=WORK bash "$0" "$@"
fi

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
WORK="${WORK:-/tmp/dapeos-thunar-build}"
ARCH="$(dpkg --print-architecture)"
OUT="$HERE"

echo "== DapeOS: build Thunar without File System entry =="
echo "Architecture: $ARCH"
echo "Work: $WORK"
echo "Output: $OUT"

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

apt-get build-dep -y thunar

rm -rf "$WORK"
mkdir -p "$WORK"
cd "$WORK"

apt-get source thunar
SRCDIR="$(find "$WORK" -maxdepth 1 -type d -name 'thunar-*' | head -n1)"
[ -n "$SRCDIR" ] || { echo "Source directory not found" >&2; exit 1; }
cd "$SRCDIR"

for p in "$HERE/no-root.patch" "$HERE/protect-xdg.patch"; do
    patch -p1 --forward < "$p"
done

BASEVER="$(dpkg-parsechangelog -SVersion)"
NEWVER="${BASEVER}+dapeos3"
export DEBEMAIL="dapeos@localhost"
export DEBFULLNAME="DapeOS"
dch --newversion "$NEWVER" --distribution trixie \
    "Hide hardcoded File System entry in the shortcuts sidebar."

dpkg-buildpackage -b -uc -us -j"$(nproc)"

for pkg in thunar thunar-data; do
    DEB="$(find "$WORK" -maxdepth 1 -name "${pkg}_${NEWVER}_${ARCH}.deb" | head -n1)"
    [ -n "$DEB" ] || DEB="$(find "$WORK" -maxdepth 1 -name "${pkg}_*_${ARCH}.deb" | head -n1)"
    [ -n "$DEB" ] || DEB="$(find "$WORK" -maxdepth 1 -name "${pkg}_*_all.deb" | head -n1)"
    [ -n "$DEB" ] || { echo "Built $pkg .deb not found" >&2; exit 1; }
    cp -v "$DEB" "$OUT/"
done

echo
echo "Hotovo. Nainstaluj oba .deb:"
echo "  apt-get install -y $OUT/thunar_*_${ARCH}.deb $OUT/thunar-data_*_${ARCH}.deb"
echo "  apt-mark hold thunar thunar-data"
