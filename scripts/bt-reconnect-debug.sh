#!/bin/bash
set -u
MAC="${1:-14:14:7D:C3:82:5E}"
LOG=/tmp/bt-reconnect-debug.log
: > "$LOG"
{
  echo "=== initial ==="
  bluetoothctl info "$MAC"
  pactl list short cards
  echo "=== power off ==="
  bluetoothctl power off
  sleep 3
  echo "=== power on ==="
  bluetoothctl power on
  sleep 3
  echo "=== state after power on ==="
  bluetoothctl info "$MAC"
  echo "=== connect ==="
  bluetoothctl connect "$MAC" 2>&1
  sleep 3
  echo "=== state after connect ==="
  bluetoothctl info "$MAC"
  pactl list short cards
} >> "$LOG" 2>&1
cat "$LOG"
