#!/usr/bin/env python3
import argparse
import ast
import fcntl
import json
import os
import re
import subprocess

import tempfile
import time
from contextlib import contextmanager
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / 'wallpaper' / 'Theme.js'
SPECTRUM = ROOT / 'wallpaper-spectrum' / 'Theme.js'
STATE = ROOT / 'main' / 'ThemeControlState.js'
SHELL_THEME = ROOT / 'main' / 'ShellTheme.js'
THEMES = ROOT / 'themes'
HYPRLAND = Path.home() / '.config' / 'hypr' / 'hyprland.lua'
KITTY = Path.home() / '.config' / 'kitty' / 'kitty.conf'
KITTY_THEME = KITTY.parent / 'theme-current.conf'
NVIM = Path.home() / '.config' / 'nvim'
NVIM_THEME = NVIM / 'colors' / 'theme-current.lua'
AVATAR_REGISTRY = ROOT / 'avatars' / 'registry.json'
AVATAR_CONTROL = ROOT / 'main' / 'avatar-control.py'
RUNTIME_DIR = Path(os.environ.get('XDG_RUNTIME_DIR', f'/run/user/{os.getuid()}'))
LOCK = Path(os.environ.get('QUICKSHELL_THEME_LOCK', RUNTIME_DIR / 'quickshell-theme-control.lock'))
AVATAR_POLICY = RUNTIME_DIR / 'quickshell-avatar-enabled'
AVATAR_POLICY_STATE = RUNTIME_DIR / 'quickshell-avatar-policy.json'
WALLPAPER_KEYS = ('wallpaperSource', 'perScreenWallpapers', 'sourceType',
                  'fitMode', 'imageOpacity', 'dimOpacity', 'dimColor', 'mirror',
                  'loopVideo', 'autoPlay', 'playbackRate')
SPECTRUM_EFFECT_KEYS = ('heightFraction', 'gain', 'opacity', 'hueOffset', 'frameRate',
                        'barsEnabled', 'wallpaperColorEffectEnabled', 'wallpaperHueBinCount',
                        'wallpaperColorEffectIdleDelayMs', 'wallpaperColorEffectFadeDurationMs')
EFFECT_KEYS = SPECTRUM_EFFECT_KEYS + ('avatarEnabled',)
AVATAR_ADAPTERS = {'hk47-hologram', 'static-portrait'}
PERSONALITY_ID_RE = re.compile(r'[a-z0-9][a-z0-9_-]*\Z')
HERMES_BIN = Path(os.environ.get('HERMES_BIN', str(Path.home() / '.local/bin/hermes')))
PERSONALITIES = Path(os.environ.get('HERMES_HOME', str(Path.home() / '.hermes'))) / 'personalities'


def load_avatar_registry() -> dict[str, dict]:
    data = json.loads(AVATAR_REGISTRY.read_text())
    avatars = data.get('avatars') if isinstance(data, dict) else None
    if data.get('version') != 1 or not isinstance(avatars, dict) or not avatars:
        raise RuntimeError(f'invalid avatar registry: {AVATAR_REGISTRY}')
    validated = {}
    for avatar_id, entry in avatars.items():
        if not re.fullmatch(r'[a-z0-9][a-z0-9_-]*', str(avatar_id)):
            raise RuntimeError(f'invalid avatar identifier: {avatar_id!r}')
        if not isinstance(entry, dict):
            raise RuntimeError(f'avatar {avatar_id} registry entry must be an object')
        config = entry.get('config')
        target = entry.get('ipcTarget')
        adapter = entry.get('adapter')
        assets = entry.get('requiredAssets')
        if not isinstance(config, str) or not re.fullmatch(r'[A-Za-z0-9_-]+', config):
            raise RuntimeError(f'avatar {avatar_id} has an invalid config')
        if not isinstance(target, str) or not re.fullmatch(r'[A-Za-z][A-Za-z0-9_]*', target):
            raise RuntimeError(f'avatar {avatar_id} has an invalid IPC target')
        if adapter not in AVATAR_ADAPTERS:
            raise RuntimeError(f'avatar {avatar_id} has an unsupported adapter')
        if not isinstance(assets, list) or not assets or any(not isinstance(path, str) or not path for path in assets):
            raise RuntimeError(f'avatar {avatar_id} has invalid required assets')
        validated[str(avatar_id)] = dict(entry)
    return validated


def resolve_avatar_profile(avatar_id: str) -> dict:
    registry = load_avatar_registry()
    if avatar_id not in registry:
        raise RuntimeError(f'unknown avatar: {avatar_id!r}')
    entry = dict(registry[avatar_id])
    config_dir = (ROOT / entry['config']).resolve()
    if config_dir.parent != ROOT.resolve() or not config_dir.is_dir():
        raise RuntimeError(f'avatar {avatar_id} has no approved config directory: {config_dir}')
    resolved_assets = []
    for asset in entry['requiredAssets']:
        path = Path(os.path.expandvars(asset)).expanduser()
        if not path.is_absolute():
            path = (config_dir / path).resolve()
            try:
                path.relative_to(config_dir)
            except ValueError as error:
                raise RuntimeError(f'avatar {avatar_id} asset escapes its config directory: {asset}') from error
        if not path.is_file():
            raise RuntimeError(f'avatar {avatar_id} required asset is missing: {path}')
        resolved_assets.append(str(path))
    entry.update(id=avatar_id, configPath=str(config_dir), resolvedAssets=resolved_assets)
    return entry


def resolve_personality_profile(personality_id: str) -> Path:
    if not isinstance(personality_id, str) or not PERSONALITY_ID_RE.fullmatch(personality_id):
        raise RuntimeError(f'invalid personality identifier: {personality_id!r}')
    root = PERSONALITIES.resolve()
    path = (root / personality_id / 'SOUL.md').resolve()
    try:
        path.relative_to(root)
    except ValueError as error:
        raise RuntimeError(f'personality escapes approved root: {personality_id!r}') from error
    if not path.is_file():
        raise RuntimeError(f'personality SOUL.md is missing: {path}')
    return path


def persist_personality(personality_id: str) -> None:
    resolve_personality_profile(personality_id)
    result = subprocess.run(
        [str(HERMES_BIN), 'config', 'set', 'display.personality', personality_id],
        check=False, capture_output=True, text=True,
    )
    if result.returncode != 0:
        detail = (result.stderr or result.stdout).strip()
        raise RuntimeError(f'could not persist personality {personality_id!r}: {detail}')


def portable_home(path: str) -> str:
    home = str(Path.home())
    value = str(path)
    return '$HOME' + value[len(home):] if value == home or value.startswith(home + os.sep) else value


@contextmanager
def operation_lock(already_held: bool = False):
    if already_held:
        yield
        return
    with LOCK.open('w') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise SystemExit('another theme operation is already in progress')
        yield


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


def updated_var(text: str, path: Path, name: str, value: str) -> str:
    pattern = rf'(?m)^(var {re.escape(name)}\s*=\s*).*$'
    updated, count = re.subn(pattern, rf'\g<1>{value}', text)
    if count != 1:
        raise RuntimeError(f'expected one {name} assignment in {path}, found {count}')
    return updated


def replace_files_atomically(updates: dict[Path, str]) -> None:
    originals = {path: path.read_text() for path in updates}
    temporary: dict[Path, str] = {}
    replaced: list[Path] = []
    try:
        for path, content in updates.items():
            fd, tmp = tempfile.mkstemp(prefix=path.name + '.', dir=path.parent)
            with os.fdopen(fd, 'w') as handle:
                handle.write(content)
            os.chmod(tmp, path.stat().st_mode)
            temporary[path] = tmp
        for path, tmp in temporary.items():
            os.replace(tmp, path)
            replaced.append(path)
            temporary[path] = ''
    except BaseException:
        for path in reversed(replaced):
            fd, rollback = tempfile.mkstemp(prefix=path.name + '.rollback.', dir=path.parent)
            try:
                with os.fdopen(fd, 'w') as handle:
                    handle.write(originals[path])
                os.chmod(rollback, path.stat().st_mode)
                os.replace(rollback, path)
            finally:
                if os.path.exists(rollback):
                    os.unlink(rollback)
        raise
    finally:
        for tmp in temporary.values():
            if tmp and os.path.exists(tmp):
                os.unlink(tmp)


def js_value(value) -> str:
    encoded = json.dumps(value, separators=(',', ':'), ensure_ascii=False)
    return f'({encoded})' if isinstance(value, dict) else encoded


def theme_color(palette: dict, source: str, alpha: str | None = None) -> str:
    value = str(palette[source]).lower()
    if len(value) == 9:
        value = value[:7]
    return value + (alpha or '')


def external_theme_files(palette: dict) -> dict[Path, str]:
    """Render the selector palette into Hyprland and Kitty consumer formats."""
    active_a = theme_color(palette, '#8fcdf0', 'ee')
    active_b = theme_color(palette, '#3b88a3', 'ee')
    inactive = '#00000000'
    shadow = '0x' + theme_color(palette, '#10161b', 'ee')[1:]
    hypr = HYPRLAND.read_text()
    assignments = {
        'theme_active_border_a': json.dumps(f'rgba({active_a[1:]})'),
        'theme_active_border_b': json.dumps(f'rgba({active_b[1:]})'),
        'theme_inactive_border': json.dumps(f'rgba({inactive[1:]})'),
        'theme_shadow': shadow,
    }
    for name, value in assignments.items():
        hypr, count = re.subn(rf'(?m)^(local {name}\s*=\s*).+$', rf'\g<1>{value}', hypr)
        if count != 1:
            raise RuntimeError(f'expected one theme assignment {name} in {HYPRLAND}')

    kitty_colors = {
        'background': theme_color(palette, '#0b1720'),
        'foreground': theme_color(palette, '#ffffff'),
        'cursor': theme_color(palette, '#8fcdf0'),
        'cursor_text_color': theme_color(palette, '#0b1720'),
        'selection_background': theme_color(palette, '#3b88a3'),
        'selection_foreground': theme_color(palette, '#ffffff'),
        'color0': theme_color(palette, '#0b1720'),
        'color1': theme_color(palette, '#d36a6a'),
        'color2': theme_color(palette, '#69c486'),
        'color3': theme_color(palette, '#ffd37d'),
        'color4': theme_color(palette, '#3b88a3'),
        'color5': theme_color(palette, '#d7bdff'),
        'color6': theme_color(palette, '#33c6e48b'),
        'color7': theme_color(palette, '#c8c8c8'),
        'color8': theme_color(palette, '#858585'),
        'color9': theme_color(palette, '#ff9098'),
        'color10': theme_color(palette, '#a8e6a3'),
        'color11': theme_color(palette, '#ffdca0'),
        'color12': theme_color(palette, '#8fcdf0'),
        'color13': theme_color(palette, '#d7bdff'),
        'color14': theme_color(palette, '#a9d8ea'),
        'color15': theme_color(palette, '#ffffff'),
    }
    kitty = '# Generated by Quickshell theme selector. Do not edit.\n'
    kitty += ''.join(f'{key} {value}\n' for key, value in kitty_colors.items())
    nvim = '''-- Generated by Quickshell theme selector. Do not edit.\n'''
    nvim += 'vim.cmd("highlight clear")\nvim.g.colors_name = "theme-current"\n'
    colors = {
        'bg': theme_color(palette, '#0b1720'), 'bg_alt': theme_color(palette, '#10161b'),
        'fg': theme_color(palette, '#ffffff'), 'muted': theme_color(palette, '#858585'),
        'accent': theme_color(palette, '#3b88a3'), 'bright': theme_color(palette, '#8fcdf0'),
        'red': theme_color(palette, '#d36a6a'), 'green': theme_color(palette, '#69c486'),
        'yellow': theme_color(palette, '#ffd37d'), 'purple': theme_color(palette, '#d7bdff'),
        'cyan': theme_color(palette, '#a9d8ea'),
    }
    nvim += 'local c = {' + ', '.join(f'{key} = "{value}"' for key, value in colors.items()) + '}\n'
    nvim += '''local function hi(group, opts) vim.api.nvim_set_hl(0, group, opts) end
hi("Normal", { fg = c.fg, bg = c.bg })
hi("NormalFloat", { fg = c.fg, bg = c.bg_alt })
hi("FloatBorder", { fg = c.accent, bg = c.bg_alt })
hi("CursorLine", { bg = c.bg_alt })
hi("CursorLineNr", { fg = c.bright, bold = true })
hi("LineNr", { fg = c.muted })
hi("Visual", { bg = c.accent, fg = c.fg })
hi("Search", { bg = c.yellow, fg = c.bg })
hi("IncSearch", { bg = c.bright, fg = c.bg })
hi("StatusLine", { fg = c.fg, bg = c.bg_alt })
hi("StatusLineNC", { fg = c.muted, bg = c.bg_alt })
hi("WinSeparator", { fg = c.accent })
hi("Directory", { fg = c.bright })
hi("Comment", { fg = c.muted, italic = true })
hi("Constant", { fg = c.cyan })
hi("String", { fg = c.green })
hi("Character", { fg = c.green })
hi("Number", { fg = c.yellow })
hi("Boolean", { fg = c.yellow })
hi("Identifier", { fg = c.bright })
hi("Function", { fg = c.bright, bold = true })
hi("Statement", { fg = c.purple })
hi("Keyword", { fg = c.purple })
hi("Type", { fg = c.cyan })
hi("Special", { fg = c.accent })
hi("Error", { fg = c.red, bold = true })
hi("DiagnosticError", { fg = c.red })
hi("DiagnosticWarn", { fg = c.yellow })
hi("DiagnosticInfo", { fg = c.bright })
hi("DiagnosticHint", { fg = c.green })
'''
    return {HYPRLAND: hypr, KITTY_THEME: kitty, NVIM_THEME: nvim}


def atomic_runtime_write(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=path.name + '.', dir=path.parent)
    try:
        with os.fdopen(fd, 'w') as handle:
            handle.write(content)
        os.chmod(temporary, 0o600)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def write_avatar_policy(enabled: bool, avatar_id: str | None = None) -> None:
    if avatar_id is None:
        avatar_id = str(state_value('selectedAvatarId'))
    resolve_avatar_profile(avatar_id)
    atomic_runtime_write(AVATAR_POLICY, '1\n' if enabled else '0\n')
    atomic_runtime_write(AVATAR_POLICY_STATE, json.dumps({
        'enabled': bool(enabled),
        'avatarId': avatar_id,
        'revision': time.time_ns(),
    }, separators=(',', ':')) + '\n')


def restore_avatar_policy(previous: str | None, previous_state: str | None = None) -> None:
    if previous is None:
        AVATAR_POLICY.unlink(missing_ok=True)
    else:
        atomic_runtime_write(AVATAR_POLICY, previous)
    if previous_state is None:
        AVATAR_POLICY_STATE.unlink(missing_ok=True)
    else:
        atomic_runtime_write(AVATAR_POLICY_STATE, previous_state)


def available_themes() -> list[dict[str, str]]:
    themes = []
    for path in sorted(THEMES.glob('*.json')):
        try:
            data = load_theme(path.stem)
        except (OSError, json.JSONDecodeError, RuntimeError):
            continue
        theme_id = str(data.get('id', ''))
        if theme_id != path.stem or not re.fullmatch(r'[A-Za-z0-9_-]+', theme_id):
            continue
        themes.append({
            'id': theme_id,
            'name': str(data.get('name', theme_id)),
            'description': str(data.get('description', '')),
        })
    return themes


def load_theme(theme_id: str) -> dict:
    if not re.fullmatch(r'[A-Za-z0-9_-]+', theme_id):
        raise RuntimeError(f'invalid theme identifier: {theme_id!r}')
    path = THEMES / f'{theme_id}.json'
    data = json.loads(path.read_text())
    if not isinstance(data, dict):
        raise RuntimeError(f'theme root must be an object: {path}')
    if data.get('id') != theme_id:
        raise RuntimeError(f'theme id does not match filename: {path}')
    avatar_id = data.get('avatarId')
    if not isinstance(avatar_id, str) or avatar_id not in load_avatar_registry():
        raise RuntimeError(f'theme {theme_id} has an unknown avatarId: {avatar_id!r}')
    personality_id = data.get('personalityId')
    resolve_personality_profile(personality_id)
    for section in ('palette', 'wallpaper', 'effects'):
        if not isinstance(data.get(section), dict):
            raise RuntimeError(f'theme {theme_id} has no {section} object')
    for name in WALLPAPER_KEYS:
        if name not in data['wallpaper']:
            raise RuntimeError(f'theme {theme_id} wallpaper is missing {name}')
    for name in EFFECT_KEYS:
        if name not in data['effects']:
            raise RuntimeError(f'theme {theme_id} effects are missing {name}')

    wallpaper = data['wallpaper']
    effects = data['effects']
    if not isinstance(wallpaper['wallpaperSource'], str) or not wallpaper['wallpaperSource']:
        raise RuntimeError(f'theme {theme_id} has an invalid wallpaperSource')
    if not isinstance(wallpaper['perScreenWallpapers'], dict):
        raise RuntimeError(f'theme {theme_id} has invalid perScreenWallpapers')
    if any(not isinstance(key, str) or not isinstance(value, str)
           for key, value in wallpaper['perScreenWallpapers'].items()):
        raise RuntimeError(f'theme {theme_id} has invalid per-screen wallpaper entries')
    if wallpaper['sourceType'] not in ('auto', 'image', 'video'):
        raise RuntimeError(f'theme {theme_id} has an invalid sourceType')
    if wallpaper['fitMode'] not in ('crop', 'fit', 'stretch'):
        raise RuntimeError(f'theme {theme_id} has an invalid fitMode')
    for name in ('mirror', 'loopVideo', 'autoPlay'):
        if type(wallpaper[name]) is not bool:
            raise RuntimeError(f'theme {theme_id} wallpaper {name} must be boolean')

    def number(section: dict, name: str, minimum: float, maximum: float,
               integer: bool = False) -> None:
        value = section[name]
        expected = int if integer else (int, float)
        if type(value) not in ((int,) if integer else expected) or not minimum <= value <= maximum:
            raise RuntimeError(f'theme {theme_id} {name} is outside {minimum}..{maximum}')

    number(wallpaper, 'imageOpacity', 0, 1)
    number(wallpaper, 'dimOpacity', 0, 1)
    number(wallpaper, 'playbackRate', 0.1, 16)
    if not isinstance(wallpaper['dimColor'], str) or not re.fullmatch(
            r'#[0-9a-fA-F]{6}(?:[0-9a-fA-F]{2})?', wallpaper['dimColor']):
        raise RuntimeError(f'theme {theme_id} has an invalid dimColor')

    for name in ('barsEnabled', 'wallpaperColorEffectEnabled', 'avatarEnabled'):
        if type(effects[name]) is not bool:
            raise RuntimeError(f'theme {theme_id} effect {name} must be boolean')
    number(effects, 'heightFraction', 0.05, 1)
    number(effects, 'gain', 0, 16)
    number(effects, 'opacity', 0, 1)
    number(effects, 'hueOffset', 0, 1)
    number(effects, 'frameRate', 1, 240, integer=True)
    number(effects, 'wallpaperHueBinCount', 1, 4096, integer=True)
    number(effects, 'wallpaperColorEffectIdleDelayMs', 0, 3600000, integer=True)
    number(effects, 'wallpaperColorEffectFadeDurationMs', 0, 60000, integer=True)

    palette = {}
    for source, target in data['palette'].items():
        source = str(source).lower()
        target = str(target).lower()
        if not re.fullmatch(r'#[0-9a-f]{6}(?:[0-9a-f]{2})?', source):
            raise RuntimeError(f'invalid palette source {source!r}')
        if not re.fullmatch(r'#[0-9a-f]{6}(?:[0-9a-f]{2})?', target):
            raise RuntimeError(f'invalid palette target {target!r}')
        palette[source] = target
    for source in ('#0b1720', '#10161b', '#3b88a3', '#69c486', '#858585',
                   '#8fcdf0', '#a8e6a3', '#a9d8ea', '#d36a6a', '#d7bdff',
                   '#ffd37d', '#ffdca0', '#ff9098', '#ffffff', '#33c6e48b',
                   '#c8c8c8'):
        if source not in palette:
            raise RuntimeError(f'theme {theme_id} palette lacks external color {source}')
    identity_path = THEMES / 'HK-47_Theme.json'
    identity = json.loads(identity_path.read_text())
    identity_palette = identity.get('palette', {}) if isinstance(identity, dict) else {}
    expected_palette = {str(key).lower() for key in identity_palette}
    if set(palette) != expected_palette:
        missing = sorted(expected_palette - set(palette))
        extra = sorted(set(palette) - expected_palette)
        raise RuntimeError(f'theme {theme_id} palette mismatch; missing={missing}, extra={extra}')
    required_palette = {
        match.group(1).lower()
        for qml in (ROOT / 'main').glob('*.qml')
        for match in re.finditer(r'ShellTheme\.color\("(#[0-9a-fA-F]{6}(?:[0-9a-fA-F]{2})?)"\)', qml.read_text())
    }
    if required_palette and expected_palette != required_palette:
        raise RuntimeError('HK-47_Theme palette does not match the shell color contract')
    data['palette'] = palette
    return data


def apply_theme(theme_id: str) -> tuple[bool, bool, bool]:
    theme = load_theme(theme_id)
    resolve_avatar_profile(theme['avatarId'])
    wallpaper = theme['wallpaper']
    effects = theme['effects']

    originals = {path: path.read_text() for path in (SHELL_THEME, STATE, BASE, SPECTRUM, HYPRLAND)}
    updates = originals.copy()
    updates[HYPRLAND] = external_theme_files(theme['palette'])[HYPRLAND]
    previous_policy = AVATAR_POLICY.read_text() if AVATAR_POLICY.exists() else None
    previous_policy_state = AVATAR_POLICY_STATE.read_text() if AVATAR_POLICY_STATE.exists() else None
    previous_kitty_theme = KITTY_THEME.read_text() if KITTY_THEME.exists() else None
    previous_nvim_theme = NVIM_THEME.read_text() if NVIM_THEME.exists() else None

    def assign(path: Path, name: str, value: str) -> None:
        updates[path] = updated_var(updates[path], path, name, value)

    assign(SHELL_THEME, 'selectedTheme', js_value(theme_id))
    assign(SHELL_THEME, 'palette', js_value(theme['palette']))
    assign(STATE, 'selectedTheme', js_value(theme_id))
    assign(STATE, 'selectedAvatarId', js_value(theme['avatarId']))

    for name in WALLPAPER_KEYS:
        value = js_value(wallpaper[name])
        assign(BASE, name, value)
        assign(SPECTRUM, name, value)

    for name in SPECTRUM_EFFECT_KEYS:
        assign(SPECTRUM, name, js_value(effects[name]))

    bars = bool(effects['barsEnabled'])
    wallpaper_enabled = bool(effects['wallpaperColorEffectEnabled'])
    avatar = bool(effects.get('avatarEnabled', False))
    assign(STATE, 'wallpaperSource', js_value(wallpaper['wallpaperSource']))
    assign(STATE, 'perScreenWallpapers', js_value(wallpaper['perScreenWallpapers']))
    assign(STATE, 'barsEnabled', js_value(bars))
    assign(STATE, 'wallpaperEnabled', js_value(wallpaper_enabled))
    assign(STATE, 'avatarEnabled', js_value(avatar))
    replace_files_atomically(updates)
    try:
        generated = external_theme_files(theme['palette'])
        atomic_runtime_write(KITTY_THEME, generated[KITTY_THEME])
        atomic_runtime_write(NVIM_THEME, generated[NVIM_THEME])
        write_avatar_policy(avatar, theme['avatarId'])
        persist_personality(theme['personalityId'])
    except BaseException:
        replace_files_atomically(originals)
        if previous_kitty_theme is None:
            KITTY_THEME.unlink(missing_ok=True)
        else:
            atomic_runtime_write(KITTY_THEME, previous_kitty_theme)
        if previous_nvim_theme is None:
            NVIM_THEME.unlink(missing_ok=True)
        else:
            atomic_runtime_write(NVIM_THEME, previous_nvim_theme)
        restore_avatar_policy(previous_policy, previous_policy_state)
        raise
    return bars, wallpaper_enabled, avatar


def reload_external_consumers() -> None:
    result = subprocess.run(['hyprctl', 'reload'], check=False, capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(f'Hyprland reload failed: {(result.stderr or result.stdout).strip()}')
    subprocess.run(['pkill', '-USR1', '-x', 'kitty'], check=False,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def apply_custom_settings(args) -> None:
    originals = {path: path.read_text() for path in (SHELL_THEME, STATE, BASE, SPECTRUM)}
    updates = originals.copy()
    previous_policy = AVATAR_POLICY.read_text() if AVATAR_POLICY.exists() else None
    previous_policy_state = AVATAR_POLICY_STATE.read_text() if AVATAR_POLICY_STATE.exists() else None

    def assign(path: Path, name: str, value: str) -> None:
        updates[path] = updated_var(updates[path], path, name, value)

    assign(SHELL_THEME, 'selectedTheme', js_value('custom'))
    assign(STATE, 'selectedTheme', js_value('custom'))

    if args.screen is not None:
        if args.screen_wallpaper is None:
            raise RuntimeError('--screen requires --screen-wallpaper')
        match = re.search(r'(?m)^var perScreenWallpapers\s*=\s*\((.*)\)\s*$', updates[BASE])
        if not match:
            raise RuntimeError('perScreenWallpapers is missing from wallpaper Theme.js')
        wallpapers = ast.literal_eval(match.group(1))
        if not isinstance(wallpapers, dict):
            raise RuntimeError('perScreenWallpapers is not a dictionary')
        source = portable_home(args.screen_wallpaper.removeprefix('file://'))
        if source:
            wallpapers[args.screen] = source
        else:
            wallpapers.pop(args.screen, None)
        encoded = js_value(wallpapers)
        assign(BASE, 'perScreenWallpapers', encoded)
        assign(SPECTRUM, 'perScreenWallpapers', encoded)
        assign(STATE, 'perScreenWallpapers', encoded)
    elif args.screen_wallpaper is not None:
        raise RuntimeError('--screen-wallpaper requires --screen')
    elif args.source:
        source = portable_home(args.source.removeprefix('file://'))
        encoded = js_value(source)
        assign(BASE, 'wallpaperSource', encoded)
        assign(SPECTRUM, 'wallpaperSource', encoded)
        assign(STATE, 'wallpaperSource', encoded)

    assign(SPECTRUM, 'barsEnabled', js_value(bool(args.bars)))
    assign(SPECTRUM, 'wallpaperColorEffectEnabled', js_value(bool(args.wallpaper)))
    assign(STATE, 'barsEnabled', js_value(bool(args.bars)))
    assign(STATE, 'wallpaperEnabled', js_value(bool(args.wallpaper)))
    assign(STATE, 'avatarEnabled', js_value(bool(args.avatar)))
    replace_files_atomically(updates)
    try:
        write_avatar_policy(bool(args.avatar), str(state_value('selectedAvatarId')))
    except BaseException:
        replace_files_atomically(originals)
        restore_avatar_policy(previous_policy, previous_policy_state)
        raise


def get_screen_wallpapers() -> dict[str, str]:
    text = BASE.read_text()
    match = re.search(r'(?m)^var perScreenWallpapers\s*=\s*\((.*)\)\s*$', text)
    if not match:
        raise RuntimeError('perScreenWallpapers is missing from wallpaper Theme.js')
    value = ast.literal_eval(match.group(1))
    if not isinstance(value, dict):
        raise RuntimeError('perScreenWallpapers is not a dictionary')
    return {str(key): str(path) for key, path in value.items()}


def state_value(name: str):
    text = STATE.read_text()
    match = re.search(rf'(?m)^var {re.escape(name)}\s*=\s*(.+)$', text)
    if not match:
        raise RuntimeError(f'{name} is missing from {STATE}')
    value = match.group(1).strip()
    if value == 'true':
        return True
    if value == 'false':
        return False
    return ast.literal_eval(value)


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


def kill_all_avatars() -> None:
    subprocess.run(['python', str(AVATAR_CONTROL), 'kill-all'], check=True,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def wait_gone(profile: Path, timeout: float = 5.0) -> None:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        result = subprocess.run(['quickshell', 'list', '--all'], check=False,
                                capture_output=True, text=True)
        if result.returncode != 0:
            time.sleep(0.1)
            continue
        profile_line = f'Config path: {profile}/shell.qml'
        if profile_line not in result.stdout:
            return
        time.sleep(0.1)
    raise RuntimeError(f'profile did not terminate: {profile}')


def wait_present(profile: Path, timeout: float = 8.0) -> None:
    deadline = time.monotonic() + timeout
    profile_line = f'Config path: {profile}/shell.qml'
    while time.monotonic() < deadline:
        result = subprocess.run(['quickshell', 'list', '--all'], check=False,
                                capture_output=True, text=True)
        if result.returncode == 0 and profile_line in result.stdout:
            return
        time.sleep(0.1)
    raise RuntimeError(f'profile did not start: {profile}')


def start(script: Path) -> None:
    subprocess.Popen(['bash', str(script)], start_new_session=True,
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def reload_main(expected_theme: str, timeout: float = 8.0) -> None:
    profile = ROOT / 'main'
    result = subprocess.run(
        ['quickshell', 'ipc', '-p', str(profile), 'call', 'lifecycle', 'reloadTheme'],
        check=False, capture_output=True, text=True,
    )
    if result.returncode != 0:
        raise RuntimeError(f'main reload request failed: {result.stderr.strip()}')
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        state = subprocess.run(
            ['quickshell', 'ipc', '-p', str(profile), 'call', 'lifecycle', 'state'],
            check=False, capture_output=True, text=True,
        )
        if state.returncode == 0:
            try:
                if json.loads(state.stdout).get('currentTheme') == expected_theme:
                    return
            except json.JSONDecodeError:
                pass
        time.sleep(0.1)
    raise RuntimeError(f'main profile did not reload theme {expected_theme}')


def restart_wallpapers(args) -> None:
    spectrum = ROOT / 'wallpaper-spectrum'
    wallpaper = ROOT / 'wallpaper'
    mode_file = Path(os.environ.get('XDG_RUNTIME_DIR', f'/run/user/{os.getuid()}')) / 'quickshell-display-mode'
    game_mode = mode_file.read_text().strip() == 'game' if mode_file.exists() else False

    if game_mode:
        kill(spectrum)
        wait_gone(spectrum)
        kill(wallpaper)
        wait_gone(wallpaper)
        start(wallpaper / 'start.sh')
        wait_present(wallpaper)
    elif args.bars or args.wallpaper:
        kill(spectrum)
        wait_gone(spectrum)
        kill(wallpaper)
        wait_gone(wallpaper)
        start(spectrum / 'start.sh')
        wait_present(spectrum)
    else:
        kill(spectrum)
        wait_gone(spectrum)
        kill(wallpaper)
        wait_gone(wallpaper)
        start(wallpaper / 'start.sh')
        wait_present(wallpaper)

    # Chatterbox owns lazy avatar creation. Theme state only permits or blocks it.
    if game_mode or not args.avatar or getattr(args, 'avatar_changed', False):
        kill_all_avatars()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('--list-json', action='store_true')
    parser.add_argument('--theme')
    parser.add_argument('--restore-current', action='store_true')
    parser.add_argument('--no-main-reload', action='store_true', help=argparse.SUPPRESS)
    parser.add_argument('--lock-held', action='store_true', help=argparse.SUPPRESS)
    parser.add_argument('--no-restart', action='store_true', help=argparse.SUPPRESS)
    parser.add_argument('--source')
    parser.add_argument('--screen')
    parser.add_argument('--screen-wallpaper')
    parser.add_argument('--bars', type=int, choices=(0, 1))
    parser.add_argument('--wallpaper', type=int, choices=(0, 1))
    parser.add_argument('--avatar', type=int, choices=(0, 1))
    args = parser.parse_args()

    if args.list_json:
        print(json.dumps(available_themes()))
        return


    with operation_lock(args.lock_held):
        if args.theme:
            previous_files = {path: path.read_text() for path in (SHELL_THEME, STATE, BASE, SPECTRUM, HYPRLAND)}
            previous_kitty_theme = KITTY_THEME.read_text() if KITTY_THEME.exists() else None
            previous_nvim_theme = NVIM_THEME.read_text() if NVIM_THEME.exists() else None
            previous = argparse.Namespace(
                bars=bool(state_value('barsEnabled')),
                wallpaper=bool(state_value('wallpaperEnabled')),
                avatar=bool(state_value('avatarEnabled')),
                avatar_id=str(state_value('selectedAvatarId')),
                avatar_changed=True,
            )
            bars, wallpaper_enabled, avatar = apply_theme(args.theme)
            if not args.no_restart:
                themed = argparse.Namespace(
                    bars=bars,
                    wallpaper=wallpaper_enabled,
                    avatar=avatar,
                    avatar_changed=(previous.avatar_id != str(state_value('selectedAvatarId'))),
                )
                try:
                    reload_external_consumers()
                    restart_wallpapers(themed)
                    if not args.no_main_reload:
                        reload_main(args.theme)
                except BaseException:
                    replace_files_atomically(previous_files)
                    if previous_kitty_theme is None:
                        KITTY_THEME.unlink(missing_ok=True)
                    else:
                        atomic_runtime_write(KITTY_THEME, previous_kitty_theme)
                    if previous_nvim_theme is None:
                        NVIM_THEME.unlink(missing_ok=True)
                    else:
                        atomic_runtime_write(NVIM_THEME, previous_nvim_theme)
                    reload_external_consumers()
                    write_avatar_policy(previous.avatar)
                    restart_wallpapers(previous)
                    raise
            return

        if args.restore_current:
            current = argparse.Namespace(
                bars=bool(state_value('barsEnabled')),
                wallpaper=bool(state_value('wallpaperEnabled')),
                avatar=bool(state_value('avatarEnabled')),
                avatar_changed=False,
            )
            restart_wallpapers(current)
            return

        if args.bars is None or args.wallpaper is None or args.avatar is None:
            parser.error('--bars, --wallpaper, and --avatar are required for effect updates')

        previous_files = {path: path.read_text() for path in (SHELL_THEME, STATE, BASE, SPECTRUM)}
        previous = argparse.Namespace(
            bars=bool(state_value('barsEnabled')),
            wallpaper=bool(state_value('wallpaperEnabled')),
            avatar=bool(state_value('avatarEnabled')),
            avatar_changed=False,
        )
        apply_custom_settings(args)
        if not args.no_restart:
            try:
                restart_wallpapers(args)
            except BaseException:
                replace_files_atomically(previous_files)
                write_avatar_policy(previous.avatar)
                restart_wallpapers(previous)
                raise


if __name__ == '__main__':
    main()
