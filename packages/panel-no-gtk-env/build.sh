#!/bin/bash
# Build xfce4-panel that strips GTK_THEME after init so launched apps use the
# system theme, while the panel keeps its own dark/light theme.
set -euo pipefail

if [ "$EUID" -ne 0 ]; then
    exec sudo --preserve-env=WORK bash "$0" "$@"
fi

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
WORK="${WORK:-/tmp/dapeos-panel-build}"
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

apt-get build-dep -y xfce4-panel

rm -rf "$WORK"
mkdir -p "$WORK"
cd "$WORK"
apt-get source xfce4-panel
SRCDIR="$(find "$WORK" -maxdepth 1 -type d -name 'xfce4-panel-*' | head -n1)"
[ -n "$SRCDIR" ] || { echo "Source directory not found" >&2; exit 1; }
cd "$SRCDIR"

patch -p1 --forward < "$HERE/panel-noenv.patch"

BASEVER="$(dpkg-parsechangelog -SVersion)"
NEWVER="${BASEVER}+dapeos1"
export DEBEMAIL="dapeos@localhost"
export DEBFULLNAME="DapeOS"
dch --newversion "$NEWVER" --distribution trixie \
    "Do not leak GTK_THEME to applications launched from the panel."

dpkg-buildpackage -b -uc -us -j"$(nproc)"

for pkg in xfce4-panel libxfce4panel-2.0-4; do
    DEB="$(find "$WORK" -maxdepth 1 -name "${pkg}_*_${ARCH}.deb" | head -n1)"
    [ -n "$DEB" ] || { echo "Built $pkg .deb not found" >&2; exit 1; }
    cp -v "$DEB" "$OUT/"
done
