#!/bin/sh
# Recover a selector process left behind after its FloatingWindow closes.
profile_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
old_pids=$(pgrep -f "^qs( -d)? -n -p ${profile_dir}$" || true)
if [ -n "$old_pids" ]; then
    kill $old_pids 2>/dev/null || true
    sleep 0.1
fi
exec qs -n -p "$profile_dir"
