#!/usr/bin/env python3
"""Exercise safe live navigation, replacement, picker dismissal, and races."""
import json
from pathlib import Path
import runpy
import time

root = Path(__file__).resolve().parent
api = runpy.run_path(str(root / 'lifecycle-live.py'))
run, ipc, state, wait, bounds = [api[n] for n in ('run', 'ipc', 'state', 'await_state', 'bounds')]
evidence = Path.home() / '.hermes/plans/quickshell-lifecycle-evidence'
original = json.loads(run('hyprctl', 'activewindow', '-j')).get('address')
cursor = json.loads(run('hyprctl', 'cursorpos', '-j'))
results = []


def click(x, y):
    run('hyprctl', 'dispatch', f'hl.dsp.cursor.move({{x={int(x)},y={int(y)}}})')
    run('python', str(root / 'desktop-input.py'), 'click')


def record(name):
    results.append({'test': name, 'state': state()})
    print('PASS', name, flush=True)


try:
    # Pointer-opened calendar closes on a click in the blank taskbar region.
    pid = json.loads(run('quickshell', 'list', '-c', 'main', '--json'))[0]['pid']
    layers = json.loads(run('hyprctl', 'layers', '-j'))
    bar = next(layer for output in layers.values() for level in output['levels'].values()
               for layer in level if layer['pid'] == pid and layer['namespace'] == 'quickshell')
    click(bar['x'] + bar['w'] - 90, bar['y'] + 19)
    wait(lambda s: s['calendar']['live'])
    click(bar['x'] + 400, bar['y'] + 19)
    wait(lambda s: not s['calendar']['live'])
    record('taskbar calendar opens and outside dismissal destroys')

    for _ in range(3):
        ipc('open', 'calendar')
        s = wait(lambda s: s['calendar']['live'])['calendar']
        x, y, w, h = bounds('calendar', s)
        expected = (s['month'] + 1) % 12
        click(x + w - 28, y + 26)
        wait(lambda s: s['calendar']['month'] == expected)
        ipc('close', 'calendar')
        wait(lambda s: not s['calendar']['live'])
    record('calendar navigation after three recreations')

    ipc('open', 'hardware')
    s = wait(lambda s: s['session']['samples'] >= 2, 30)
    session_count = s['session']['created']
    x, y, w, h = bounds('hardware', s['hardware'])
    click(x + w - 68, y + 29)
    s = wait(lambda s: s['details']['live'] and not s['hardware']['live'])
    assert s['hardware']['created'] == s['hardware']['destroyed']
    assert s['session']['created'] == session_count
    x, y, w, h = bounds('details', s['details'])
    for tab in range(4):
        tabwidth = (w - 54) / 4
        click(x + 18 + tab * (tabwidth + 6) + tabwidth / 2, y + 74)
        wait(lambda s: s['details']['tab'] == tab)
        time.sleep(.3)
        run('grim', '-g', f'{x},{y} {w}x{h}', str(evidence / f'details-tab-{tab}.png'))
    expected_cards = sum(1 for card in Path('/sys/class/drm').glob('card[0-9]') if (card / 'device').exists())
    assert state()['session']['gpuCount'] == expected_cards, 'UI must preserve the existing sampler device inventory'
    run('python', str(root / 'desktop-input.py'), 'super+c')
    wait(lambda s: not s['hardware']['live'] and not s['details']['live'] and not s['session']['live'])
    record('real Details click replaces summary, one sampler, all four tabs, native close')

    # Reopen requested immediately during sampler teardown must survive.
    for _ in range(8):
        ipc('open', 'hardware')
        wait(lambda s: s['hardware']['live'])
        ipc('close', 'hardware')
        ipc('open', 'hardware')
        wait(lambda s: s['hardware']['live'] and s['session']['live'])
        ipc('close', 'hardware')
        wait(lambda s: not s['hardware']['live'] and not s['session']['live'])
    record('eight hardware close-immediate-reopen cycles')

    ipc('open', 'theme')
    wait(lambda s: s['theme']['live'])
    x, y, w, h = bounds('theme', state()['theme'])
    click(x + 230, y + 182)
    wait(lambda s: s['themeResources']['picker']['live'])
    active = json.loads(run('hyprctl', 'activewindow', '-j'))
    assert active.get('title') == 'Choose HK-47 artwork', active
    run('grim', '-g', f'{active["at"][0]},{active["at"][1]} {active["size"][0]}x{active["size"][1]}', str(evidence / 'picker.png'))
    run('python', str(root / 'desktop-input.py'), 'super+c')
    wait(lambda s: s['theme']['live'] and not s['themeResources']['picker']['live'])
    click(x + 230, y + 182)
    wait(lambda s: s['themeResources']['picker']['live'])
    ipc('close', 'theme')
    wait(lambda s: not s['theme']['live'] and not s['themeResources']['picker']['live'])
    assert state()['themeResources']['picker']['created'] == state()['themeResources']['picker']['destroyed']
    record('native picker open, SUPER+C dismiss, menu close destroys open picker')

    # A different focused managed window wins over an unfocused details window.
    ipc('open', 'details')
    wait(lambda s: s['details']['live'])
    ipc('open', 'theme')
    wait(lambda s: s['theme']['live'])
    assert json.loads(run('hyprctl', 'activewindow', '-j')).get('title') == 'HK-47 Theme Control'
    run('python', str(root / 'desktop-input.py'), 'super+c')
    wait(lambda s: not s['theme']['live'])
    assert state()['details']['live']
    ipc('close', 'details')
    wait(lambda s: not s['session']['live'])
    record('SUPER+C respects focused managed window, not unfocused details')
finally:
    for name in api['NAMES']:
        ipc('close', name)
    wait(lambda s: not s['session']['live'])
    run('hyprctl', 'dispatch', f'hl.dsp.cursor.move({{x={cursor["x"]},y={cursor["y"]}}})')
    if original and any(c['address'] == original for c in json.loads(run('hyprctl', 'clients', '-j'))):
        run('hyprctl', 'dispatch', 'hl.dsp.focus({window=' + json.dumps('address:' + original) + '})')
    (evidence / 'interactions-results.json').write_text(json.dumps(results, indent=2))
