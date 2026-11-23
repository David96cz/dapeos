#!/bin/bash
set -u
MAC="${1:-14:14:7D:C3:82:5E}"
LOG=/tmp/bt-bond-debug.log
: > "$LOG"
{
  echo "=== before ==="
  bluetoothctl info "$MAC"
  echo "=== bond ==="
  bluetoothctl bond "$MAC" 2>&1
  echo "=== after bond ==="
  sleep 2
  bluetoothctl info "$MAC"
  echo "=== connect ==="
  bluetoothctl connect "$MAC" 2>&1
  sleep 2
  echo "=== after connect ==="
  bluetoothctl info "$MAC"
  echo "=== audio ==="
  pactl list short cards
} >> "$LOG" 2>&1
cat "$LOG"
