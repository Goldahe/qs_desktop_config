#!/usr/bin/env python3
"""SUPER+C: consume layer-shell popup closes before normal client close."""
import json
import subprocess

def run(*args):
    return subprocess.run(args, capture_output=True, text=True, timeout=3)

def main():
    before = json.loads(run('hyprctl', 'activewindow', '-j').stdout or '{}')
    try:
        result = run('quickshell', 'ipc', '-c', 'main', 'call', 'lifecycle', 'closeTop').stdout.strip()
    except subprocess.TimeoutExpired:
        return  # Fail closed: never kill the client behind a popup on IPC timeout.
    if result == 'closed':
        return
    if result != 'none':
        # An empty/error reply is not evidence that no popup exists. Only a
        # successfully queried, empty instance list permits ordinary fallback.
        try:
            listed = run('quickshell', 'list', '-c', 'main', '--json')
            if listed.returncode != 0 or json.loads(listed.stdout) != []:
                return
        except (ValueError, subprocess.TimeoutExpired):
            return
    after = json.loads(run('hyprctl', 'activewindow', '-j').stdout or '{}')
    address = before.get('address', '')
    if address and address == after.get('address'):
        selector = json.dumps('address:' + address)
        run('hyprctl', 'dispatch', 'hl.dsp.window.close({window=' + selector + '})')

if __name__ == '__main__':
    main()
