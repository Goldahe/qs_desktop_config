#!/usr/bin/env bash
set -euo pipefail

mode=${1:-}
state_file="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/quickshell-display-mode"

kill_profile() {
    quickshell kill -p "$1" >/dev/null 2>&1 || true
}

case "$mode" in
    game)
        # Keep only the taskbar and the static wallpaper background.
        kill_profile "/home/hawk/.config/quickshell/wallpaper-spectrum"
        kill_profile "/home/hawk/.config/quickshell/HK-47_Avatar"
        kill_profile "/home/hawk/.config/quickshell/wallpaper"
        bash "/home/hawk/.config/quickshell/wallpaper/start.sh"
        ;;
    work)
        # Replace the static background with the full reactive desktop assets.
        kill_profile "/home/hawk/.config/quickshell/wallpaper"
        bash "/home/hawk/.config/quickshell/wallpaper-spectrum/start.sh"
        bash "/home/hawk/.config/quickshell/HK-47_Avatar/start.sh"
        ;;
    *)
        printf 'usage: %s {game|work}\n' "$0" >&2
        exit 2
        ;;
esac

install -Dm600 /dev/null "$state_file"
printf '%s\n' "$mode" > "$state_file"
