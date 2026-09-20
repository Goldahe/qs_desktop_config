#!/usr/bin/env python3
"""Contract tests for the trusted avatar registry helper."""
from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import tempfile
from unittest.mock import patch

HELPER = Path(__file__).resolve().parents[1] / "avatar-control.py"


def load_helper():
    spec = importlib.util.spec_from_file_location("avatar_control", HELPER)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def fixture(module, root: Path) -> None:
    module.ROOT = root
    module.REGISTRY = root / "avatars/registry.json"
    module.STATE = root / "main/ThemeControlState.js"
    module.RUNTIME_DIR = root / "runtime"
    module.MODE_FILE = module.RUNTIME_DIR / "quickshell-display-mode"
    module.LEGACY_POLICY = module.RUNTIME_DIR / "quickshell-avatar-enabled"
    module.POLICY = module.RUNTIME_DIR / "quickshell-avatar-policy.json"
    module.LOCK = module.RUNTIME_DIR / "quickshell-theme-control.lock"
    module.RUNTIME_DIR.mkdir(parents=True)
    avatars = {
        "hk47-hologram": {
            "config": "HK-47_Avatar",
            "ipcTarget": "hk47Avatar",
            "adapter": "hk47-hologram",
            "requiredAssets": ["shell.qml"],
        },
        "shrine-maiden": {
            "config": "Shrine_Maiden_Avatar",
            "ipcTarget": "shrineMaidenAvatar",
            "adapter": "static-portrait",
            "requiredAssets": ["shell.qml", "assets/fire-keeper.png"],
        },
    }
    registry = root / "avatars/registry.json"
    registry.parent.mkdir(parents=True)
    registry.write_text(json.dumps({"version": 1, "avatars": avatars}))
    for entry in avatars.values():
        config = root / entry["config"]
        for relative in entry["requiredAssets"]:
            target = config / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text("fixture")
        launcher = config / "start.sh"
        launcher.write_text("#!/bin/sh\nexit 0\n")
        launcher.chmod(0o755)
    state = root / "main/ThemeControlState.js"
    state.parent.mkdir(parents=True)
    state.write_text('var selectedAvatarId = "shrine-maiden"\nvar avatarEnabled = true\n')


def test_current_resolves_committed_avatar_policy() -> None:
    module = load_helper()
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        fixture(module, root)
        module.MODE_FILE.write_text("work\n")
        module.POLICY.write_text(json.dumps({
            "enabled": True, "avatarId": "shrine-maiden", "revision": 9,
        }))

        current = module.current_avatar()

        assert current["id"] == "shrine-maiden"
        assert current["adapter"] == "static-portrait"
        assert current["ipcTarget"] == "shrineMaidenAvatar"
        assert current["revision"] == 9


def test_game_mode_rejects_launch_even_when_policy_is_enabled() -> None:
    module = load_helper()
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        fixture(module, root)
        module.MODE_FILE.write_text("game\n")
        module.POLICY.write_text(json.dumps({
            "enabled": True, "avatarId": "shrine-maiden", "revision": 9,
        }))

        assert module.avatar_allowed("shrine-maiden") is False


def test_launch_uses_approved_profile_launcher_not_direct_quickshell() -> None:
    module = load_helper()
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        fixture(module, root)
        module.MODE_FILE.write_text("work\n")
        module.POLICY.write_text(json.dumps({
            "enabled": True, "avatarId": "shrine-maiden", "revision": 9,
        }))

        with patch.object(module.subprocess, "run") as run:
            module.launch_avatar("shrine-maiden")

        run.assert_called_once_with(
            ["bash", str(root / "Shrine_Maiden_Avatar/start.sh")],
            check=True,
            close_fds=True,
        )


def test_kill_all_does_not_depend_on_avatar_assets_remaining_present() -> None:
    module = load_helper()
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        fixture(module, root)
        (root / "Shrine_Maiden_Avatar/assets/fire-keeper.png").unlink()

        with patch.object(module.shutil, "which", return_value="/usr/bin/quickshell"), patch.object(
            module.subprocess, "run"
        ) as run, patch.object(module, "wait_profile_gone"):
            module.kill_all()

        killed = {call.args[0][-1] for call in run.call_args_list}
        assert killed == {
            str(root / "HK-47_Avatar"),
            str(root / "Shrine_Maiden_Avatar"),
        }


def test_kill_waits_until_profile_is_verified_absent() -> None:
    module = load_helper()
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        fixture(module, root)
        config_path = root / "Shrine_Maiden_Avatar"
        present = type("Result", (), {
            "returncode": 0,
            "stdout": f"Config path: {config_path}/shell.qml\n",
        })()
        absent = type("Result", (), {"returncode": 0, "stdout": ""})()
        killed = type("Result", (), {"returncode": 1, "stdout": ""})()

        with patch.object(module.shutil, "which", return_value="/usr/bin/quickshell"), patch.object(
            module.subprocess, "run", side_effect=[killed, present, absent]
        ) as run:
            module.kill_avatar("shrine-maiden")

        assert run.call_count == 3


def test_wait_profile_gone_rejects_persistent_profile() -> None:
    module = load_helper()
    config_path = Path("/tmp/avatar")
    present = type("Result", (), {
        "returncode": 0,
        "stdout": f"Config path: {config_path}/shell.qml\n",
    })()
    with patch.object(module.subprocess, "run", return_value=present), patch.object(
        module.time, "monotonic", side_effect=[0.0, 0.0, 2.0]
    ), patch.object(module.time, "sleep"):
        try:
            module.wait_profile_gone(config_path, "/usr/bin/quickshell", timeout=1.0)
        except RuntimeError as error:
            assert "did not terminate" in str(error)
        else:
            raise AssertionError("persistent avatar profile was accepted as terminated")


def test_wait_profile_gone_rejects_repeated_list_failures() -> None:
    module = load_helper()
    failed = type("Result", (), {
        "returncode": 1,
        "stdout": "",
        "stderr": "list failed",
    })()
    with patch.object(module.subprocess, "run", return_value=failed), patch.object(
        module.time, "monotonic", side_effect=[0.0, 0.0, 2.0]
    ), patch.object(module.time, "sleep"):
        try:
            module.wait_profile_gone(Path("/tmp/avatar"), "/usr/bin/quickshell", timeout=1.0)
        except RuntimeError as error:
            assert "list failed" in str(error)
        else:
            raise AssertionError("failed profile-list reads were accepted as termination")


def test_live_shrine_profile_is_static_click_through_and_amd_launched() -> None:
    profile = Path(__file__).resolve().parents[2] / "Shrine_Maiden_Avatar"
    portrait = (profile / "Portrait.qml").read_text()
    shell = (profile / "shell.qml").read_text()
    launcher = (profile / "start.sh").read_text()

    assert "WlrLayer.Overlay" in portrait
    assert "mask: Region {}" in portrait
    assert "ShaderEffect" not in portrait
    assert "Timer {" in portrait
    assert "implicitHeight: 384" in portrait
    assert "* 0.8" in portrait
    assert "bottom: portrait.taskbarHeight + 3" in portrait
    assert "FireKeeper_idle.png" in portrait
    assert "FireKeeper_open.png" in portrait
    assert "FireKeeper_open_O.png" in portrait
    assert "FireKeeper_open_more.png" in portrait
    assert "mouthBand(value)" in portrait
    assert "mouthOpenThreshold: 0.10" in portrait
    assert "mouthOThreshold: 0.30" in portrait
    assert "mouthMoreThreshold: 0.58" in portrait
    registry = json.loads((profile.parent / "avatars/registry.json").read_text())
    assert registry["avatars"]["shrine-maiden"]["requiredAssets"][-2:] == [
        "$HOME/Avatar/FireKeeper_open_more.png",
        "$HOME/Avatar/FireKeeper_open_O.png",
    ]
    assert "function setAmplitudeEnvelope" in portrait
    assert "function showAvatar()" in portrait
    assert "function hideAvatar()" in portrait
    assert 'target: "shrineMaidenAvatar"' in shell
    assert 'Quickshell.env("HOME")' in shell
    assert "function activate(): void" in shell
    assert "function deactivate(): void" in shell
    assert "function setAmplitudeEnvelope(envelope: string)" in shell
    assert "MESA_VK_DEVICE_SELECT=1002:747e" in launcher
    assert 'CUDA_VISIBLE_DEVICES=""' in launcher


def test_hk_profile_rechecks_selected_avatar_at_launcher_and_qml_boundaries() -> None:
    profile = Path(__file__).resolve().parents[2] / "HK-47_Avatar"
    shell = (profile / "shell.qml").read_text()
    launcher = (profile / "start.sh").read_text()
    assert "avatar-control.py" in shell
    assert 'Quickshell.env("HOME")' in shell
    assert '"allowed", "hk47-hologram"' in shell
    assert "avatar-control.py allowed hk47-hologram" in launcher


if __name__ == "__main__":
    test_current_resolves_committed_avatar_policy()
    test_game_mode_rejects_launch_even_when_policy_is_enabled()
    test_launch_uses_approved_profile_launcher_not_direct_quickshell()
    test_kill_all_does_not_depend_on_avatar_assets_remaining_present()
    test_kill_waits_until_profile_is_verified_absent()
    test_wait_profile_gone_rejects_persistent_profile()
    test_wait_profile_gone_rejects_repeated_list_failures()
    test_live_shrine_profile_is_static_click_through_and_amd_launched()
    test_hk_profile_rechecks_selected_avatar_at_launcher_and_qml_boundaries()
    print("PASS: trusted avatar control contract")
