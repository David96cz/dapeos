#!/bin/bash
set -e
cd "$(dirname "$0")/.."

packages/dapeos-quicksettings-c/build-deb.sh
sudo apt-get install -y --reinstall ./packages/dapeos-quicksettings-c/dapeos-quicksettings-c_1.0_amd64.deb
sudo install -m755 contents/xfce/scripts/dapeos-toggle-wifi /usr/local/bin/dapeos-toggle-wifi

pkill -9 -f '[d]apeos-quicksettings' 2>/dev/null || true
sleep 0.3
: > /tmp/dapeos-qs-geometry.log
: > /tmp/dapeos-qs-signal.log
: > /tmp/dapeos-qs.out

dapeos-quicksettings-c >/tmp/dapeos-qs.out 2>&1 &
sleep 1
dapeos-toggle-wifi
sleep 1

echo "--- signal log ---"
cat /tmp/dapeos-qs-signal.log 2>/dev/null || true
echo "--- geometry log ---"
cat /tmp/dapeos-qs-geometry.log 2>/dev/null || true
echo "--- app stderr ---"
cat /tmp/dapeos-qs.out 2>/dev/null || true
