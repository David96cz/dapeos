#!/bin/sh
state_dir="${XDG_DATA_HOME:-$HOME/.local/share}/albert"
mkdir -p "$state_dir" 2>/dev/null
ver="$(albert --version 2>/dev/null | awk '{print $NF}')"
[ -n "$ver" ] && printf '[General]\nlast_used_version=%s\n' "$ver" > "$state_dir/state"
exec albert