#!/bin/sh
set -eu
profile_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
old_pids=$(pgrep -f "^qs( -d)? -n -p ${profile_dir}$" || true)
if [ -n "$old_pids" ]; then
    kill $old_pids 2>/dev/null || true
    sleep 0.1
fi
exec qs -n -p "$profile_dir"
