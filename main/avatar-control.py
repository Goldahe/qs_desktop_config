#!/usr/bin/env python3
"""Resolve and control trusted theme-selected Quickshell avatars."""
from __future__ import annotations

import argparse
import fcntl
import json
import os
import re
import shutil
import subprocess
import time
from contextlib import contextmanager
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REGISTRY = ROOT / "avatars" / "registry.json"
STATE = ROOT / "main" / "ThemeControlState.js"
RUNTIME_DIR = Path(os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}"))
MODE_FILE = RUNTIME_DIR / "quickshell-display-mode"
LEGACY_POLICY = RUNTIME_DIR / "quickshell-avatar-enabled"
POLICY = RUNTIME_DIR / "quickshell-avatar-policy.json"
LOCK = Path(os.environ.get("QUICKSHELL_THEME_LOCK", RUNTIME_DIR / "quickshell-theme-control.lock"))
ADAPTERS = {"hk47-hologram", "static-portrait"}


def _state_value(name: str):
    text = STATE.read_text()
    match = re.search(rf"(?m)^var {re.escape(name)}\s*=\s*(.+)$", text)
    if not match:
        raise RuntimeError(f"{name} is missing from {STATE}")
    raw = match.group(1).strip()
    if raw == "true":
        return True
    if raw == "false":
        return False
    return json.loads(raw)


def load_registry() -> dict[str, dict]:
    data = json.loads(REGISTRY.read_text())
    avatars = data.get("avatars") if isinstance(data, dict) else None
    if data.get("version") != 1 or not isinstance(avatars, dict) or not avatars:
        raise RuntimeError(f"invalid avatar registry: {REGISTRY}")
    return avatars


def resolve_avatar(avatar_id: str) -> dict:
    if not re.fullmatch(r"[a-z0-9][a-z0-9_-]*", str(avatar_id)):
        raise RuntimeError(f"invalid avatar identifier: {avatar_id!r}")
    entry = load_registry().get(avatar_id)
    if not isinstance(entry, dict):
        raise RuntimeError(f"unknown avatar: {avatar_id!r}")
    config = entry.get("config")
    target = entry.get("ipcTarget")
    adapter = entry.get("adapter")
    assets = entry.get("requiredAssets")
    if not isinstance(config, str) or not re.fullmatch(r"[A-Za-z0-9_-]+", config):
        raise RuntimeError(f"avatar {avatar_id} has an invalid config")
    if not isinstance(target, str) or not re.fullmatch(r"[A-Za-z][A-Za-z0-9_]*", target):
        raise RuntimeError(f"avatar {avatar_id} has an invalid IPC target")
    if adapter not in ADAPTERS:
        raise RuntimeError(f"avatar {avatar_id} has an unsupported adapter")
    if not isinstance(assets, list) or not assets:
        raise RuntimeError(f"avatar {avatar_id} has no required assets")

    config_path = (ROOT / config).resolve()
    if config_path.parent != ROOT.resolve() or not config_path.is_dir():
        raise RuntimeError(f"avatar {avatar_id} config is unavailable: {config_path}")
    for asset in assets:
        if not isinstance(asset, str) or not asset:
            raise RuntimeError(f"avatar {avatar_id} has an invalid asset entry")
        asset_path = Path(os.path.expandvars(asset)).expanduser()
        if not asset_path.is_absolute():
            asset_path = (config_path / asset_path).resolve()
            try:
                asset_path.relative_to(config_path)
            except ValueError as error:
                raise RuntimeError(f"avatar {avatar_id} asset escapes its config: {asset}") from error
        if not asset_path.is_file():
            raise RuntimeError(f"avatar {avatar_id} required asset is missing: {asset_path}")

    launcher = config_path / "start.sh"
    if not launcher.is_file():
        raise RuntimeError(f"avatar {avatar_id} launcher is missing: {launcher}")
    return {
        "id": avatar_id,
        "config": config,
        "configPath": str(config_path),
        "ipcTarget": target,
        "adapter": adapter,
        "launcher": str(launcher),
    }


def current_avatar() -> dict:
    enabled = bool(_state_value("avatarEnabled"))
    avatar_id = str(_state_value("selectedAvatarId"))
    revision = 0
    if POLICY.is_file():
        policy = json.loads(POLICY.read_text())
        if not isinstance(policy, dict):
            raise RuntimeError(f"invalid avatar policy: {POLICY}")
        enabled = policy.get("enabled")
        avatar_id = policy.get("avatarId")
        revision = policy.get("revision", 0)
        if type(enabled) is not bool or not isinstance(avatar_id, str) or type(revision) is not int:
            raise RuntimeError(f"invalid avatar policy fields: {POLICY}")
    elif LEGACY_POLICY.is_file():
        enabled = LEGACY_POLICY.read_text().strip() != "0"

    resolved = resolve_avatar(avatar_id)
    resolved.update(enabled=enabled, revision=revision)
    return resolved


def game_mode_active() -> bool:
    try:
        return MODE_FILE.read_text().strip() == "game"
    except OSError:
        return False


def avatar_allowed(avatar_id: str) -> bool:
    if game_mode_active():
        return False
    current = current_avatar()
    return current["enabled"] and current["id"] == avatar_id


def launch_avatar(avatar_id: str) -> None:
    if not avatar_allowed(avatar_id):
        raise RuntimeError(f"avatar {avatar_id} is not allowed by current mode/policy")
    avatar = resolve_avatar(avatar_id)
    subprocess.run(["bash", avatar["launcher"]], check=True, close_fds=True)


def kill_avatar(avatar_id: str) -> None:
    entry = load_registry().get(avatar_id)
    if not isinstance(entry, dict):
        raise RuntimeError(f"unknown avatar: {avatar_id!r}")
    config = entry.get("config")
    if not isinstance(config, str) or not re.fullmatch(r"[A-Za-z0-9_-]+", config):
        raise RuntimeError(f"avatar {avatar_id} has an invalid config")
    config_path = (ROOT / config).resolve()
    if config_path.parent != ROOT.resolve():
        raise RuntimeError(f"avatar {avatar_id} config escapes the approved root")
    quickshell = shutil.which("quickshell") or shutil.which("qs")
    if quickshell is None:
        raise RuntimeError("Quickshell CLI is unavailable")
    subprocess.run(
        [quickshell, "kill", "-p", str(config_path)],
        check=False,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    wait_profile_gone(config_path, quickshell)


def wait_profile_gone(config_path: Path, quickshell: str, timeout: float = 5.0) -> None:
    marker = f"Config path: {config_path}/shell.qml"
    deadline = time.monotonic() + timeout
    last_error = ""
    while time.monotonic() < deadline:
        result = subprocess.run(
            [quickshell, "list", "--all"],
            check=False,
            capture_output=True,
            text=True,
        )
        if result.returncode == 0:
            if marker not in result.stdout:
                return
        else:
            last_error = getattr(result, "stderr", "").strip()
        time.sleep(0.1)
    detail = f": {last_error}" if last_error else ""
    raise RuntimeError(f"avatar profile did not terminate: {config_path}{detail}")


def kill_all() -> None:
    for avatar_id in load_registry():
        kill_avatar(avatar_id)


@contextmanager
def operation_lock():
    LOCK.parent.mkdir(parents=True, exist_ok=True)
    with LOCK.open("w") as lock:
        fcntl.flock(lock.fileno(), fcntl.LOCK_EX)
        yield


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=("current", "allowed", "launch", "kill", "kill-all", "validate"))
    parser.add_argument("avatar_id", nargs="?")
    args = parser.parse_args()

    if args.action == "current":
        print(json.dumps(current_avatar(), separators=(",", ":")))
        return
    if args.action == "validate":
        for avatar_id in load_registry():
            resolve_avatar(avatar_id)
        return
    if args.action == "kill-all":
        kill_all()
        return
    if not args.avatar_id:
        parser.error(f"{args.action} requires avatar_id")
    if args.action == "allowed":
        raise SystemExit(0 if avatar_allowed(args.avatar_id) else 1)
    if args.action == "kill":
        kill_avatar(args.avatar_id)
        return
    with operation_lock():
        launch_avatar(args.avatar_id)


if __name__ == "__main__":
    main()
