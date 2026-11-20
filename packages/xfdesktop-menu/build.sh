#!/bin/bash
# Build xfdesktop with Create Launcher removed and Appearance added.
set -euo pipefail

if [ "$EUID" -ne 0 ]; then
    exec sudo --preserve-env=WORK bash "$0" "$@"
fi

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
WORK="${WORK:-/tmp/dapeos-xfdesktop-build}"
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

apt-get build-dep -y xfdesktop4

rm -rf "$WORK"
mkdir -p "$WORK"
cd "$WORK"
apt-get source xfdesktop4
SRCDIR="$(find "$WORK" -maxdepth 1 -type d -name 'xfdesktop*-4.*' | head -n1)"
[ -n "$SRCDIR" ] || SRCDIR="$(find "$WORK" -maxdepth 1 -type d -name 'xfdesktop*' | head -n1)"
[ -n "$SRCDIR" ] || { echo "Source directory not found" >&2; exit 1; }
cd "$SRCDIR"

patch -p1 --forward < "$HERE/menu.patch"

BASEVER="$(dpkg-parsechangelog -SVersion)"
NEWVER="${BASEVER}+dapeos1"
export DEBEMAIL="dapeos@localhost"
export DEBFULLNAME="DapeOS"
dch --newversion "$NEWVER" --distribution trixie \
    "Remove Create Launcher and add Appearance to the desktop menu."

dpkg-buildpackage -b -uc -us -j"$(nproc)"

for pkg in xfdesktop4 xfdesktop4-data; do
    DEB="$(find "$WORK" -maxdepth 1 -name "${pkg}_${NEWVER}_${ARCH}.deb" | head -n1)"
    [ -n "$DEB" ] || DEB="$(find "$WORK" -maxdepth 1 -name "${pkg}_*_${ARCH}.deb" | head -n1)"
    [ -n "$DEB" ] || DEB="$(find "$WORK" -maxdepth 1 -name "${pkg}_*_all.deb" | head -n1)"
    [ -n "$DEB" ] || { echo "Built $pkg .deb not found" >&2; exit 1; }
    cp -v "$DEB" "$OUT/"
done

echo "Hotovo: $OUT"
