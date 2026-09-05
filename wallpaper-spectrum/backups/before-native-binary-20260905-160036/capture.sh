#!/usr/bin/env bash
# stdout: 640 normalized CSV bins at 60 Hz; all diagnostics go to stderr.
# SPECTRUM_SINK overrides the exact sink name (not its .monitor source).
# Keep this supervisor alive: it owns/reaps both sides of the audio pipe.
set -Eeuo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
if [[ -n ${SPECTRUM_SINK:-} ]]; then
    sink=$SPECTRUM_SINK
elif ! sink=$(pactl get-default-sink); then
    printf 'capture.sh: cannot query default sink\n' >&2
    exit 1
fi
if [[ -z $sink || $sink == *$'\n'* ]]; then
    printf 'capture.sh: expected one nonempty exact sink name\n' >&2
    exit 1
fi
if [[ ! -x $root/fft-spectrum ]] || ! command -v parec >/dev/null; then
    printf 'capture.sh: fft-spectrum executable or parec is missing\n' >&2
    exit 1
fi
capture_pid=
analyzer_pid=
pipe_dir=
cleanup() {
    local status=$?
    trap - EXIT TERM INT HUP
    # Both children exec directly, so their tracked PIDs are the real processes.
    [[ -z $capture_pid ]] || kill -TERM "$capture_pid" 2>/dev/null || :
    [[ -z $analyzer_pid ]] || kill -TERM "$analyzer_pid" 2>/dev/null || :
    [[ -z $capture_pid ]] || wait "$capture_pid" 2>/dev/null || :
    [[ -z $analyzer_pid ]] || wait "$analyzer_pid" 2>/dev/null || :
    [[ -z $pipe_dir ]] || rm -rf -- "$pipe_dir"
    exit "$status"
}
trap cleanup EXIT
trap 'exit 143' TERM
trap 'exit 130' INT
trap 'exit 129' HUP
# A private FIFO is a kernel pipe, without an untracked pipeline subshell.
pipe_dir=$(mktemp -d "${TMPDIR:-/tmp}/wallpaper-spectrum.XXXXXXXX")
mkfifo -- "$pipe_dir/audio"
printf 'capture.sh: capturing %s.monitor at 48000 Hz stereo, latency 16 ms\n' "$sink" >&2
(exec "$root/fft-spectrum" <"$pipe_dir/audio") &
analyzer_pid=$!
(exec parec --device="$sink.monitor" --format=float32le --rate=48000 --channels=2 --raw --latency-msec=16 >"$pipe_dir/audio") &
capture_pid=$!
status=0
wait -n "$capture_pid" "$analyzer_pid" || status=$?
printf 'capture.sh: audio pipeline ended (status %s)\n' "$status" >&2
exit "$status"
