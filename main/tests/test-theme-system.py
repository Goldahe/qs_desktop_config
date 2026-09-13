#!/usr/bin/env python3
"""Contract tests for selectable shell themes without touching live profiles."""
from __future__ import annotations

import ast
import fcntl
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def assignment(path: Path, name: str):
    text = path.read_text()
    match = re.search(rf"(?m)^var {re.escape(name)}\s*=\s*(.+)$", text)
    assert match, f"missing {name} in {path}"
    value = match.group(1).strip()
    if value.startswith("(") and value.endswith(")"):
        value = value[1:-1]
    if value == "true":
        return True
    if value == "false":
        return False
    if value == "null":
        return None
    return ast.literal_eval(value)


def copy_fixture(target: Path) -> None:
    for relative in (
        "main/theme-control.py",
        "main/ThemeControlState.js",
        "main/ShellTheme.js",
        "wallpaper/Theme.js",
        "wallpaper-spectrum/Theme.js",
    ):
        source = ROOT / relative
        destination = target / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, destination)
    shutil.copytree(ROOT / "themes", target / "themes")


def run_controller(root: Path, *arguments: str,
                   environment: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
    if environment is None:
        environment = os.environ.copy()
        runtime = root / "runtime"
        runtime.mkdir(exist_ok=True)
        environment["XDG_RUNTIME_DIR"] = str(runtime)
    return subprocess.run(
        [sys.executable, str(root / "main/theme-control.py"), *arguments],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
        env=environment,
    )


def load_controller(root: Path):
    path = root / "main/theme-control.py"
    spec = importlib.util.spec_from_file_location("isolated_theme_control", path)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def mutable_files(root: Path) -> tuple[Path, ...]:
    return tuple(root / relative for relative in (
        "main/ShellTheme.js",
        "main/ThemeControlState.js",
        "wallpaper/Theme.js",
        "wallpaper-spectrum/Theme.js",
    ))


def test_theme_apply_rolls_back_every_destination_on_replace_failure() -> None:
    with tempfile.TemporaryDirectory(prefix="qs-theme-transaction-") as directory:
        root = Path(directory)
        copy_fixture(root)
        controller = load_controller(root)
        before = {path: path.read_text() for path in mutable_files(root)}
        real_replace = controller.os.replace
        failed = False

        def fail_one_replace(source, destination):
            nonlocal failed
            if Path(destination) == controller.STATE and not failed:
                failed = True
                raise OSError("simulated destination failure")
            return real_replace(source, destination)

        controller.os.replace = fail_one_replace
        try:
            try:
                controller.apply_theme("HK-47_Amber_Theme")
            except OSError as error:
                assert "simulated destination failure" in str(error)
            else:
                raise AssertionError("simulated replacement failure was not surfaced")
        finally:
            controller.os.replace = real_replace

        assert failed
        for path, content in before.items():
            assert path.read_text() == content, f"failed apply left mixed state in {path}"


def test_theme_apply_rolls_back_when_avatar_policy_write_fails() -> None:
    with tempfile.TemporaryDirectory(prefix="qs-theme-policy-transaction-") as directory:
        root = Path(directory)
        copy_fixture(root)
        controller = load_controller(root)
        controller.AVATAR_POLICY = root / "runtime/quickshell-avatar-enabled"
        before = {path: path.read_text() for path in mutable_files(root)}

        def fail_policy(_enabled):
            raise OSError("simulated policy failure")

        controller.write_avatar_policy = fail_policy
        try:
            controller.apply_theme("HK-47_Amber_Theme")
        except OSError as error:
            assert "simulated policy failure" in str(error)
        else:
            raise AssertionError("policy failure was not surfaced")

        for path, content in before.items():
            assert path.read_text() == content, f"policy failure left mixed state in {path}"


def test_controller_rejects_an_overlapping_write_operation() -> None:
    with tempfile.TemporaryDirectory(prefix="qs-theme-lock-") as directory:
        root = Path(directory)
        copy_fixture(root)
        lock_path = root / ".theme-control.lock"
        with lock_path.open("w") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            environment = os.environ.copy()
            environment["QUICKSHELL_THEME_LOCK"] = str(lock_path)
            result = run_controller(root, "--theme", "HK-47_Amber_Theme", "--no-restart",
                                    environment=environment)

        assert result.returncode != 0
        assert "already in progress" in result.stderr


def test_home_compaction_respects_path_boundaries_in_python_and_qml() -> None:
    controller = load_controller(ROOT)
    home = str(Path.home())
    assert controller.portable_home(home) == "$HOME"
    assert controller.portable_home(home + "/wallpaper.png") == "$HOME/wallpaper.png"
    assert controller.portable_home(home + "2/wallpaper.png") == home + "2/wallpaper.png"

    for relative in (
        "main/ThemeControl.qml",
        "main/ThemeControlState.js",
        "wallpaper/Theme.js",
        "wallpaper/WallpaperSurface.qml",
        "wallpaper-spectrum/Theme.js",
        "wallpaper-spectrum/WallpaperSurface.qml",
    ):
        text = (ROOT / relative).read_text()
        if relative == "main/ThemeControl.qml":
            assert 'value === root.homeDir || value.indexOf(root.homeDir + "/") === 0' in text
        assert 'value === "$HOME" || value.indexOf("$HOME/") === 0' in text


def test_manual_wallpaper_or_effect_change_marks_theme_custom() -> None:
    with tempfile.TemporaryDirectory(prefix="qs-theme-custom-") as directory:
        root = Path(directory)
        copy_fixture(root)
        result = run_controller(
            root, "--source", "file:///tmp/manual-wallpaper.png",
            "--bars", "0", "--wallpaper", "1", "--avatar", "0", "--no-restart",
        )
        assert result.returncode == 0, result.stderr
        assert assignment(root / "main/ThemeControlState.js", "selectedTheme") == "custom"
        assert assignment(root / "main/ShellTheme.js", "selectedTheme") == "custom"
        assert assignment(root / "main/ThemeControlState.js", "wallpaperSource") == "/tmp/manual-wallpaper.png"


def test_work_mode_restores_current_theme_policy() -> None:
    script = (ROOT / "main/mode-switch.sh").read_text()
    work_case = script.split("\n    work)", 1)[1].split(";;", 1)[0]
    assert "--restore-current" in work_case
    assert "wallpaper-spectrum/start.sh" not in work_case
    assert "HK-47_Avatar/start.sh" not in work_case

    with tempfile.TemporaryDirectory(prefix="qs-mode-work-") as directory:
        sandbox = Path(directory)
        runtime = sandbox / "runtime"
        binaries = sandbox / "bin"
        runtime.mkdir()
        binaries.mkdir()
        (runtime / "quickshell-display-mode").write_text("game\n")
        log = sandbox / "python.log"
        hermes = binaries / "hermes"
        hermes.write_text("#!/bin/sh\nexit 0\n")
        hermes.chmod(0o755)
        python = binaries / "python"
        python.write_text(
            "#!/bin/sh\nprintf '%s\\n' \"$(cat \"$XDG_RUNTIME_DIR/quickshell-display-mode\") $*\" > \"$MODE_TEST_LOG\"\n"
        )
        python.chmod(0o755)
        environment = os.environ.copy()
        environment.update({
            "XDG_RUNTIME_DIR": str(runtime),
            "HERMES_BIN": str(hermes),
            "MODE_TEST_LOG": str(log),
            "PATH": str(binaries) + ":/usr/bin",
        })
        result = subprocess.run(
            ["bash", str(ROOT / "main/mode-switch.sh"), "work"],
            text=True, capture_output=True, env=environment, check=False,
        )
        assert result.returncode == 0, result.stderr
        assert (runtime / "quickshell-display-mode").read_text().strip() == "work"
        assert log.read_text().startswith("work "), log.read_text()


def test_mode_contention_never_publishes_uncommitted_marker() -> None:
    with tempfile.TemporaryDirectory(prefix="qs-mode-lock-") as directory:
        root = Path(directory)
        runtime = root / "runtime"
        runtime.mkdir()
        marker = runtime / "quickshell-display-mode"
        marker.write_text("work\n")
        lock_path = runtime / "quickshell-theme-control.lock"
        with lock_path.open("w") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            environment = os.environ.copy()
            environment.update({
                "XDG_RUNTIME_DIR": str(runtime),
                "QUICKSHELL_THEME_LOCK": str(lock_path),
                "HERMES_BIN": "/bin/true",
            })
            result = subprocess.run(
                ["bash", str(ROOT / "main/mode-switch.sh"), "game"],
                text=True, capture_output=True, env=environment, check=False,
            )
        assert result.returncode != 0
        assert marker.read_text().strip() == "work"


def test_theme_catalog_skips_malformed_json_shapes() -> None:
    with tempfile.TemporaryDirectory(prefix="qs-theme-catalog-") as directory:
        root = Path(directory)
        copy_fixture(root)
        (root / "themes/Array_Theme.json").write_text("[]")
        result = run_controller(root, "--list-json")
        assert result.returncode == 0, result.stderr
        ids = {entry["id"] for entry in json.loads(result.stdout)}
        assert "HK-47_Theme" in ids
        assert "Array_Theme" not in ids


def test_main_theme_reload_uses_verified_quickshell_ipc() -> None:
    controller = (ROOT / "main/theme-control.py").read_text()
    assert "def reload_main(expected_theme" in controller
    assert "'lifecycle', 'reloadTheme'" in controller
    assert "get('currentTheme') == expected_theme" in controller
    assert "systemd-run" not in controller


def test_every_theme_has_the_complete_identity_palette() -> None:
    identity = json.loads((ROOT / "themes/HK-47_Theme.json").read_text())["palette"]
    for path in (ROOT / "themes").glob("*.json"):
        theme = json.loads(path.read_text())
        assert set(theme["palette"]) == set(identity), path.name


def test_hk47_theme_is_discoverable_and_selected() -> None:
    with tempfile.TemporaryDirectory(prefix="qs-theme-system-") as directory:
        root = Path(directory)
        copy_fixture(root)

        listed = run_controller(root, "--list-json")
        assert listed.returncode == 0, listed.stderr
        themes = json.loads(listed.stdout)
        assert any(theme["id"] == "HK-47_Theme" for theme in themes)
        assert len(themes) >= 2, "selector needs at least two real themes"

        alternate = next(theme for theme in themes if theme["id"] != "HK-47_Theme")
        alternate_applied = run_controller(root, "--theme", alternate["id"], "--no-restart")
        assert alternate_applied.returncode == 0, alternate_applied.stderr
        alternate_palette = assignment(root / "main/ShellTheme.js", "palette")

        applied = run_controller(root, "--theme", "HK-47_Theme", "--no-restart")
        assert applied.returncode == 0, applied.stderr
        assert assignment(root / "main/ThemeControlState.js", "selectedTheme") == "HK-47_Theme"
        assert assignment(root / "main/ShellTheme.js", "selectedTheme") == "HK-47_Theme"

        preset = json.loads((root / "themes/HK-47_Theme.json").read_text())
        assert alternate_palette != preset["palette"]
        assert assignment(root / "main/ShellTheme.js", "palette") == preset["palette"]
        assert assignment(root / "wallpaper/Theme.js", "wallpaperSource") == preset["wallpaper"]["wallpaperSource"]
        assert assignment(root / "wallpaper-spectrum/Theme.js", "barsEnabled") is preset["effects"]["barsEnabled"]
        assert assignment(root / "main/ThemeControlState.js", "avatarEnabled") is preset["effects"]["avatarEnabled"]
        assert (root / "runtime/quickshell-avatar-enabled").read_text().strip() == "1"

        before = {
            relative: (root / relative).read_text()
            for relative in (
                "main/ShellTheme.js",
                "main/ThemeControlState.js",
                "wallpaper/Theme.js",
                "wallpaper-spectrum/Theme.js",
            )
        }
        broken = json.loads(json.dumps(preset))
        broken["id"] = "Broken_Theme"
        del broken["wallpaper"]["fitMode"]
        (root / "themes/Broken_Theme.json").write_text(json.dumps(broken))
        rejected = run_controller(root, "--theme", "Broken_Theme", "--no-restart")
        assert rejected.returncode != 0
        for relative, content in before.items():
            assert (root / relative).read_text() == content, f"invalid theme partially modified {relative}"

        invalid = json.loads(json.dumps(preset))
        invalid["id"] = "Invalid_Types"
        invalid["wallpaper"]["fitMode"] = "not-a-mode"
        invalid["wallpaper"]["imageOpacity"] = {"bad": "type"}
        invalid["effects"]["frameRate"] = -999
        invalid["effects"]["barsEnabled"] = "false"
        (root / "themes/Invalid_Types.json").write_text(json.dumps(invalid))
        rejected = run_controller(root, "--theme", "Invalid_Types", "--no-restart")
        assert rejected.returncode != 0
        for relative, content in before.items():
            assert (root / relative).read_text() == content, f"ill-typed theme modified {relative}"


def test_dark_souls_theme_is_complete_and_discoverable() -> None:
    with tempfile.TemporaryDirectory(prefix="qs-dark-souls-theme-") as directory:
        root = Path(directory)
        copy_fixture(root)
        listed = run_controller(root, "--list-json")
        assert listed.returncode == 0, listed.stderr
        themes = {theme["id"]: theme for theme in json.loads(listed.stdout)}
        assert "Dark_Souls_Theme" in themes
        preset = json.loads((root / "themes/Dark_Souls_Theme.json").read_text())
        identity = json.loads((root / "themes/HK-47_Theme.json").read_text())
        assert set(preset["palette"]) == set(identity["palette"])
        assert preset["palette"] != identity["palette"]
        assert preset["wallpaper"]["wallpaperSource"].endswith("Dark-Souls-Remastered-Theme.jpg")
        assert preset["effects"]["hueOffset"] > 0.0
        assert (Path.home() / "Pictures/Wallpapers/Dark-Souls-Remastered-Theme.jpg").is_file()

        preset_bytes = {
            path.name: path.read_bytes() for path in (root / "themes").glob("*.json")
        }
        applied = run_controller(root, "--theme", "Dark_Souls_Theme", "--no-restart")
        assert applied.returncode == 0, applied.stderr
        assert assignment(root / "main/ShellTheme.js", "selectedTheme") == "Dark_Souls_Theme"
        assert assignment(root / "main/ShellTheme.js", "palette") == preset["palette"]
        assert assignment(root / "wallpaper/Theme.js", "wallpaperSource") == preset["wallpaper"]["wallpaperSource"]

        restored = run_controller(root, "--theme", "HK-47_Theme", "--no-restart")
        assert restored.returncode == 0, restored.stderr
        assert assignment(root / "main/ShellTheme.js", "selectedTheme") == "HK-47_Theme"
        for path in (root / "themes").glob("*.json"):
            assert path.read_bytes() == preset_bytes[path.name], f"theme preset mutated: {path.name}"


def test_every_main_shell_color_uses_the_selected_theme() -> None:
    themed_files = 0
    for path in sorted((ROOT / "main").glob("*.qml")):
        text = path.read_text()
        matches = list(re.finditer(r'"#[0-9A-Fa-f]{6,8}"', text))
        assert not re.search(r'color\s*:\s*["\']white["\']', text), f"named white bypasses theme in {path.name}"
        if not matches:
            continue
        themed_files += 1
        assert 'import "ShellTheme.js" as ShellTheme' in text, f"{path.name} has no shell-theme import"
        for match in matches:
            prefix = text[max(0, match.start() - 18):match.start()]
            assert prefix.endswith('ShellTheme.color('), f"raw color in {path.name}: {match.group()}"
    assert themed_files >= 18

    control = (ROOT / "main/ThemeControl.qml").read_text()
    assert "themeListProcess" in control
    assert "id: themeApplyProcess" in control
    assert "operationInProgress" in control
    assert "onExited: function(exitCode" in control
    assert "operationError" in control
    assert 'text: root.operationError' in control
    accept_body = control.split("function acceptArtwork", 1)[1].split("function openMenu", 1)[0]
    assert "State.wallpaperSource =" not in accept_body
    assert "Quickshell.execDetached" not in control
    assert "Apply theme" in control
    assert "State.selectedTheme" in control
    assert "id: themePopup" in control, "theme selector popup must use the shell palette"
    assert "function openThemeChoices()" in control

    bar = (ROOT / "main/Bar.qml").read_text()
    assert "function themeChoices(): void" in bar
    assert "function themeApply(themeId: string): bool" in bar

    controller = (ROOT / "main/theme-control.py").read_text()
    assert "start(avatar / 'start.sh')" not in controller, "theme changes must not seize Chatterbox avatar ownership"


if __name__ == "__main__":
    test_theme_apply_rolls_back_every_destination_on_replace_failure()
    test_theme_apply_rolls_back_when_avatar_policy_write_fails()
    test_controller_rejects_an_overlapping_write_operation()
    test_home_compaction_respects_path_boundaries_in_python_and_qml()
    test_manual_wallpaper_or_effect_change_marks_theme_custom()
    test_work_mode_restores_current_theme_policy()
    test_mode_contention_never_publishes_uncommitted_marker()
    test_theme_catalog_skips_malformed_json_shapes()
    test_main_theme_reload_uses_verified_quickshell_ipc()
    test_every_theme_has_the_complete_identity_palette()
    test_hk47_theme_is_discoverable_and_selected()
    test_dark_souls_theme_is_complete_and_discoverable()
    test_every_main_shell_color_uses_the_selected_theme()
    print("PASS: selectable HK-47 theme contract")
