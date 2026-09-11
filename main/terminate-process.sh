#!/usr/bin/env bash
set -euo pipefail

pid=${1:-}
expected_name=${2:-}

if [[ ! "$pid" =~ ^[1-9][0-9]*$ ]] || [[ -z "$expected_name" ]]; then
    printf 'Invalid process selection.\n' >&2
    exit 2
fi

if ! kill -0 "$pid" 2>/dev/null; then
    printf 'PID %s is no longer running.\n' "$pid" >&2
    exit 3
fi

actual_name=$(ps -p "$pid" -o comm= 2>/dev/null | xargs)
if [[ "$actual_name" != "$expected_name" ]]; then
    printf 'PID %s no longer belongs to %q; refusing to signal a reused PID.\n' "$pid" "$expected_name" >&2
    exit 4
fi

kill -TERM "$pid"
printf 'SIGTERM sent to %s (PID %s).\n' "$actual_name" "$pid"
