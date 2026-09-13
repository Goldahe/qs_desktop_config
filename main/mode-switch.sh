#!/usr/bin/env bash
set -euo pipefail

mode=${1:-}
case "$mode" in
    game|work) ;;
    *)
        printf 'usage: %s {game|work}\n' "$0" >&2
        exit 2
        ;;
esac
state_file="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/quickshell-display-mode"
lock_file="${QUICKSHELL_THEME_LOCK:-${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/quickshell-theme-control.lock}"
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

exec {theme_lock_fd}>"$lock_file"
if ! flock -n "$theme_lock_fd"; then
    printf 'another theme or mode operation is already in progress\n' >&2
    exit 1
fi

previous_mode=""
if [[ -f "$state_file" ]]; then
    previous_mode=$(<"$state_file")
fi
transition_complete=0
rollback_transition() {
    if (( transition_complete )); then return; fi
    set +e
    if [[ "$previous_mode" == game ]]; then
        printf 'game\n' > "$state_file"
        set_chatterbox_plugin disabled
        kill_profile "$config_root/wallpaper-spectrum"
        python "$config_root/main/avatar-control.py" kill-all {theme_lock_fd}>&-
        kill_profile "$config_root/wallpaper"
        bash "$config_root/wallpaper/start.sh" {theme_lock_fd}>&-
    else
        # Publish Work temporarily so the mode-aware restorer reconstructs the
        # prior Work graph, then restore an originally absent marker if needed.
        printf 'work\n' > "$state_file"
        set_chatterbox_plugin enabled
        python "$config_root/main/theme-control.py" --restore-current --lock-held {theme_lock_fd}>&-
        if [[ -z "$previous_mode" ]]; then
            rm -f -- "$state_file"
        fi
    fi
}
trap rollback_transition EXIT

install -Dm600 /dev/null "$state_file"
printf '%s\n' "$mode" > "$state_file"

case "$mode" in
    game)
        # Disable Chatterbox before removing the reactive desktop assets.
        set_chatterbox_plugin disabled
        # Keep only the taskbar and the static wallpaper background.
        kill_profile "$config_root/wallpaper-spectrum"
        python "$config_root/main/avatar-control.py" kill-all {theme_lock_fd}>&-
        kill_profile "$config_root/wallpaper"
        bash "$config_root/wallpaper/start.sh" {theme_lock_fd}>&-
        ;;
    work)
        # Restore Chatterbox before replacing the static background.
        set_chatterbox_plugin enabled
        # Restore the selected theme's effect policy. Chatterbox remains the
        # sole owner of lazy avatar creation.
        python "$config_root/main/theme-control.py" --restore-current --lock-held {theme_lock_fd}>&-
        ;;
    *)
        printf 'usage: %s {game|work}\n' "$0" >&2
        exit 2
        ;;
esac

transition_complete=1
trap - EXIT
