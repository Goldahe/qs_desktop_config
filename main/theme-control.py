#!/usr/bin/env python3
import argparse
import os
import re
import subprocess
import tempfile
import time
from pathlib import Path

ROOT = Path('/home/hawk/.config/quickshell')
BASE = ROOT / 'wallpaper' / 'Theme.js'
SPECTRUM = ROOT / 'wallpaper-spectrum' / 'Theme.js'
STATE = ROOT / 'main' / 'ThemeControlState.js'

def set_var(path: Path, name: str, value: str) -> None:
    text = path.read_text()
    pattern = rf'(?m)^(var {re.escape(name)}\s*=\s*).*$'
    replacement = rf'\g<1>{value}'
    updated, count = re.subn(pattern, replacement, text)
    if count != 1:
        raise RuntimeError(f'expected one {name} assignment in {path}, found {count}')
    fd, tmp = tempfile.mkstemp(prefix=path.name + '.', dir=path.parent)
    try:
        with os.fdopen(fd, 'w') as handle:
            handle.write(updated)
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)

def kill(profile: Path) -> None:
    subprocess.run(['quickshell', 'kill', '-p', str(profile)], check=False,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

def wait_gone(profile: Path, timeout: float = 5.0) -> None:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        result = subprocess.run(['quickshell', 'list', '--all'], check=False,
                                capture_output=True, text=True)
        profile_line = f'Config path: {profile}/shell.qml'
        if profile_line not in result.stdout:
            return
        time.sleep(0.1)
    raise RuntimeError(f'profile did not terminate: {profile}')

def start(script: Path) -> None:
    subprocess.Popen(['bash', str(script)], start_new_session=True,
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('--source')
    parser.add_argument('--bars', type=int, choices=(0, 1), required=True)
    parser.add_argument('--wallpaper', type=int, choices=(0, 1), required=True)
    parser.add_argument('--avatar', type=int, choices=(0, 1), required=True)
    args = parser.parse_args()
    if args.source:
        source = args.source.removeprefix('file://')
        set_var(BASE, 'wallpaperSource', repr(source))
        set_var(SPECTRUM, 'wallpaperSource', repr(source))
        set_var(STATE, 'wallpaperSource', repr(source))
    set_var(SPECTRUM, 'barsEnabled', 'true' if args.bars else 'false')
    set_var(SPECTRUM, 'wallpaperColorEffectEnabled', 'true' if args.wallpaper else 'false')
    set_var(STATE, 'barsEnabled', 'true' if args.bars else 'false')
    set_var(STATE, 'wallpaperEnabled', 'true' if args.wallpaper else 'false')
    set_var(STATE, 'avatarEnabled', 'true' if args.avatar else 'false')

    spectrum = ROOT / 'wallpaper-spectrum'
    wallpaper = ROOT / 'wallpaper'
    avatar = ROOT / 'HK-47_Avatar'
    mode_file = Path(os.environ.get('XDG_RUNTIME_DIR', f'/run/user/{os.getuid()}')) / 'quickshell-display-mode'
    game_mode = mode_file.read_text().strip() == 'game' if mode_file.exists() else False
    if game_mode:
        kill(spectrum)
        wait_gone(spectrum)
        kill(wallpaper)
        wait_gone(wallpaper)
        start(wallpaper / 'start.sh')
        kill(avatar)
    elif args.bars or args.wallpaper:
        kill(spectrum)
        wait_gone(spectrum)
        kill(wallpaper)
        wait_gone(wallpaper)
        start(spectrum / 'start.sh')
    else:
        kill(spectrum)
        wait_gone(spectrum)
        kill(wallpaper)
        wait_gone(wallpaper)
        start(wallpaper / 'start.sh')
    if not game_mode and args.avatar:
        start(avatar / 'start.sh')
    elif not game_mode:
        kill(avatar)

if __name__ == '__main__':
    main()
