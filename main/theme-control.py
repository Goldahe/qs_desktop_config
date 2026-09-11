#!/usr/bin/env python3
import argparse
import ast
import os
import re
import subprocess
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / 'wallpaper' / 'Theme.js'
SPECTRUM = ROOT / 'wallpaper-spectrum' / 'Theme.js'
STATE = ROOT / 'main' / 'ThemeControlState.js'


def portable_home(path: str) -> str:
    home = str(Path.home())
    value = str(path)
    return '$HOME' + value[len(home):] if value.startswith(home) else value


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


def get_screen_wallpapers() -> dict[str, str]:
    text = BASE.read_text()
    match = re.search(r'(?m)^var perScreenWallpapers\s*=\s*\((.*)\)\s*$', text)
    if not match:
        raise RuntimeError('perScreenWallpapers is missing from wallpaper Theme.js')
    value = ast.literal_eval(match.group(1))
    if not isinstance(value, dict):
        raise RuntimeError('perScreenWallpapers is not a dictionary')
    return {str(key): str(path) for key, path in value.items()}


def set_screen_wallpaper(screen: str, source: str) -> None:
    wallpapers = get_screen_wallpapers()
    source = portable_home(source.removeprefix('file://'))
    if source:
        wallpapers[screen] = source
    else:
        wallpapers.pop(screen, None)
    encoded = '(' + repr(wallpapers) + ')'
    set_var(BASE, 'perScreenWallpapers', encoded)
    set_var(SPECTRUM, 'perScreenWallpapers', encoded)
    set_var(STATE, 'perScreenWallpapers', encoded)


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


def restart_wallpapers(args) -> None:
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


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('--source')
    parser.add_argument('--screen')
    parser.add_argument('--screen-wallpaper')
    parser.add_argument('--bars', type=int, choices=(0, 1), required=True)
    parser.add_argument('--wallpaper', type=int, choices=(0, 1), required=True)
    parser.add_argument('--avatar', type=int, choices=(0, 1), required=True)
    args = parser.parse_args()

    if args.screen is not None:
        if args.screen_wallpaper is None:
            raise SystemExit('--screen requires --screen-wallpaper')
        set_screen_wallpaper(args.screen, args.screen_wallpaper)
    elif args.screen_wallpaper is not None:
        raise SystemExit('--screen-wallpaper requires --screen')
    elif args.source:
        source = portable_home(args.source.removeprefix('file://'))
        set_var(BASE, 'wallpaperSource', repr(source))
        set_var(SPECTRUM, 'wallpaperSource', repr(source))
        set_var(STATE, 'wallpaperSource', repr(source))

    set_var(SPECTRUM, 'barsEnabled', 'true' if args.bars else 'false')
    set_var(SPECTRUM, 'wallpaperColorEffectEnabled', 'true' if args.wallpaper else 'false')
    set_var(STATE, 'barsEnabled', 'true' if args.bars else 'false')
    set_var(STATE, 'wallpaperEnabled', 'true' if args.wallpaper else 'false')
    set_var(STATE, 'avatarEnabled', 'true' if args.avatar else 'false')
    restart_wallpapers(args)


if __name__ == '__main__':
    main()
