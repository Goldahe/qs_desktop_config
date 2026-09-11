#!/usr/bin/env python3
"""Live lifecycle acceptance. Opens/closes only QS UI, never invokes actions.
Default: IPC recreation checks. --desktop: screenshots and physical SUPER+C.
"""
import argparse
import json
from pathlib import Path
import subprocess
import time

ROOT = Path(__file__).resolve().parent
NAMES = ['calendar', 'power', 'hardware', 'details', 'vfio', 'wifi', 'chatterbox', 'theme']
TITLES = {'details': 'HK-47 Hardware Details', 'theme': 'HK-47 Theme Control'}


def run(*args):
    p = subprocess.run(args, capture_output=True, text=True, timeout=10)
    assert p.returncode == 0, (args, p.stdout, p.stderr)
    assert not p.stdout.startswith('error:'), (args, p.stdout)
    return p.stdout.strip()


def ipc(*args):
    return run('quickshell', 'ipc', '-c', 'main', 'call', 'lifecycle', *args)


def state():
    return json.loads(ipc('state'))


def await_state(predicate, seconds=5):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        result = state()
        if predicate(result):
            return result
        time.sleep(.05)
    raise AssertionError(result)


def bounds(name, snapshot):
    if name in TITLES:
        client = next(c for c in json.loads(run('hyprctl', 'clients', '-j')) if c['title'] == TITLES[name])
        return [*client['at'], *client['size']]
    pid = json.loads(run('quickshell', 'list', '-c', 'main', '--json'))[0]['pid']
    layers = json.loads(run('hyprctl', 'layers', '-j'))
    bar = next(layer for output in layers.values() for level in output['levels'].values()
               for layer in level if layer['pid'] == pid and layer['namespace'] == 'quickshell')
    # Popup mapToGlobal is relative to the layer-shell parent's origin on Wayland.
    return [int(snapshot['x'] + bar['x']), int(snapshot['y'] + bar['y']),
            int(snapshot['width']), int(snapshot['height'])]


def cycle(name, desktop=False, evidence=None):
    before = state()[name]
    try:
        ipc('open', name)
        opened = await_state(lambda s: s[name]['live'] and s[name]['visible'])[name]
        assert opened['created'] == before['created'] + 1, opened
        time.sleep(.35)
        if desktop:
            if name in TITLES:
                client = next(c for c in json.loads(run('hyprctl', 'clients', '-j')) if c['title'] == TITLES[name])
                assert client['floating'], client
                run('hyprctl', 'dispatch', 'hl.dsp.focus({window=' + json.dumps('address:' + client['address']) + '})')
                assert json.loads(run('hyprctl', 'activewindow', '-j')).get('title') == TITLES[name]
            if name in ('hardware', 'details'):
                await_state(lambda s: s['session']['samples'] >= 2, seconds=30)
            x, y, w, h = bounds(name, state()[name])
            run('grim', '-g', f'{x},{y} {w}x{h}', str(evidence / (name + '.png')))
            if name in TITLES:
                # Sampling can take seconds; re-establish the intended
                # target immediately before emitting a global shortcut.
                run('hyprctl', 'dispatch', f'hl.dsp.cursor.move({{x={x + 80},y={y + 30}}})')
                run('hyprctl', 'dispatch', 'hl.dsp.focus({window=' + json.dumps('address:' + client['address']) + '})')
                assert json.loads(run('hyprctl', 'activewindow', '-j')).get('address') == client['address'], 'Focus changed during validation'
            run('python', str(ROOT / 'desktop-input.py'), 'super+c')
        else:
            ipc('close', name)
        closed = await_state(lambda s: not s[name]['live'] and s[name]['destroyed'] == before['destroyed'] + 1)[name]
        print(name, 'SUPER+C' if desktop else 'IPC', json.dumps(closed), flush=True)
        return closed
    finally:
        ipc('close', name)
        await_state(lambda s: not s[name]['live'] and not s[name]['closing'])
        if name in ('hardware', 'details'):
            await_state(lambda s: not s['session']['live'])


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--desktop', action='store_true')
    parser.add_argument('names', nargs='*', default=NAMES)
    args = parser.parse_args()
    evidence = Path.home() / '.hermes/plans/quickshell-lifecycle-evidence'
    evidence.mkdir(exist_ok=True)
    original = json.loads(run('hyprctl', 'activewindow', '-j')).get('address')
    cursor = json.loads(run('hyprctl', 'cursorpos', '-j'))
    results = {}
    try:
        for name in args.names or NAMES:
            assert name in NAMES
            results[name] = cycle(name, args.desktop, evidence)
    finally:
        if args.desktop:
            run('hyprctl', 'dispatch', f'hl.dsp.cursor.move({{x={cursor["x"]},y={cursor["y"]}}})')
        if original and any(c['address'] == original for c in json.loads(run('hyprctl', 'clients', '-j'))):
            run('hyprctl', 'dispatch', 'hl.dsp.focus({window=' + json.dumps('address:' + original) + '})')
    (evidence / ('desktop-results.json' if args.desktop else 'ipc-results.json')).write_text(json.dumps(results, indent=2))


if __name__ == '__main__':
    main()
