#!/usr/bin/env python3
"""Run only ThemeControl, offscreen/software; never touch desktop IPC or effects."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

source = Path(__file__).resolve().parent.parent
with tempfile.TemporaryDirectory(prefix="qs-theme-lifecycle-") as directory:
    config = Path(directory)
    target = config / "main"
    target.mkdir()
    for name in ("ThemeControl.qml", "ThemeControlState.js", "ShellTheme.js",
                 "LifecycleSlot.qml", "theme-control.py"):
        shutil.copy2(source / name, target / name)
    shutil.copytree(source.parent / "themes", config / "themes")
    # Offscreen Qt has no layer-shell PanelWindow backend. Adapt ONLY the
    # persistent corner launcher in the temporary copy, never the menu/picker.
    theme = (target / "ThemeControl.qml").read_text()
    theme = theme.replace("PanelWindow {", "FloatingWindow {", 1)
    panel_only = ("WlrLayershell.", "focusable:", "exclusionMode:", "exclusiveZone:",
                  "anchors { left: true; top: true }", "margins { left: 0; top: 0 }")
    theme = "\n".join(line for line in theme.splitlines()
                      if not any(token in line for token in panel_only))
    (target / "ThemeControl.qml").write_text(theme)
    (target / "test-artwork.svg").write_text('<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16"><rect width="16" height="16" fill="red"/></svg>')
    shutil.copy2(source / "tests/theme-lifecycle.qml", target / "shell.qml")
    env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software",
               QSG_RHI_BACKEND="software", QT_FFMPEG_DECODING_HW_DEVICE_TYPES="vaapi",
               __EGL_VENDOR_LIBRARY_FILENAMES="/usr/share/glvnd/egl_vendor.d/50_mesa.json",
               DRI_PRIME="pci-0000_03_00_0", LIBVA_DRIVER_NAME="radeonsi",
               VK_DRIVER_FILES="/usr/share/vulkan/icd.d/radeon_icd.json")
    env.pop("WAYLAND_DISPLAY", None)
    env.pop("DISPLAY", None)
    result = subprocess.run(["quickshell", "--no-color", "-p", str(target)], env=env,
                            text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=20)
    print(result.stdout)
    assert "THEME_TEST_FAIL" not in result.stdout, "Theme lifecycle assertion failed"
    assert "THEME_TEST_PASS" in result.stdout, "Theme lifecycle did not finish"
    assert result.returncode == 0, f"Quickshell exited {result.returncode}"
