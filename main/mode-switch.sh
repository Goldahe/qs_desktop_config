#!/usr/bin/env bash
set -euo pipefail

mode=${1:-}
state_file="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/quickshell-display-mode"
config_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
hermes_bin="${HERMES_BIN:-${HOME}/.local/bin/hermes}"
if [[ ! -x "$hermes_bin" ]]; then
    hermes_bin="$(command -v hermes || true)"
fi

set_chatterbox_plugin() {
    local desired="$1"
    if [[ -z "$hermes_bin" ]]; then
        printf 'hermes executable not found; cannot set Chatterbox plugin state\n' >&2
        return 1
    fi
    case "$desired" in
        enabled)  "$hermes_bin" plugins enable chatterbox-tts --no-allow-tool-override >/dev/null ;;
        disabled) "$hermes_bin" plugins disable chatterbox-tts >/dev/null ;;
        *)
            printf 'invalid Chatterbox plugin state: %s\n' "$desired" >&2
            return 2
            ;;
    esac
}

kill_profile() {
    quickshell kill -p "$1" >/dev/null 2>&1 || true
}

case "$mode" in
    game)
        # Disable Chatterbox before removing the reactive desktop assets.
        set_chatterbox_plugin disabled
        # Keep only the taskbar and the static wallpaper background.
        kill_profile "$config_root/wallpaper-spectrum"
        kill_profile "$config_root/HK-47_Avatar"
        kill_profile "$config_root/wallpaper"
        bash "$config_root/wallpaper/start.sh"
        ;;
    work)
        # Restore Chatterbox before replacing the static background.
        set_chatterbox_plugin enabled
        # Replace the static background with the full reactive desktop assets.
        kill_profile "$config_root/wallpaper"
        bash "$config_root/wallpaper-spectrum/start.sh"
        bash "$config_root/HK-47_Avatar/start.sh"
        ;;
    *)
        printf 'usage: %s {game|work}\n' "$0" >&2
        exit 2
        ;;
esac

install -Dm600 /dev/null "$state_file"
printf '%s\n' "$mode" > "$state_file"
