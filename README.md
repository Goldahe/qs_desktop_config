# qs_desktop_config

Quickshell desktop UI configuration for the Ebon Hawk.

## Active profiles

- `main/shell.qml` — taskbar, controls, popups, theme control, and mode toggle.
- `wallpaper/shell.qml` — ordinary wallpaper profile.
- `wallpaper-spectrum/shell.qml` — native audio-reactive wallpaper profile.
- `HK-47_Avatar/shell.qml` — standalone HK-47 avatar overlay.

The taskbar-owned theme control applies artwork and effect checkbox changes immediately. It does not require a separate Apply button.

## Validation

Load a profile with the installed Quickshell runtime:

```sh
timeout 8s quickshell --no-color -p /home/hawk/.config/quickshell/main/shell.qml
timeout 8s quickshell --no-color -p /home/hawk/.config/quickshell/wallpaper/shell.qml
timeout 8s quickshell --no-color -p /home/hawk/.config/quickshell/HK-47_Avatar/shell.qml
```

`Configuration Loaded` confirms that the profile parsed and initialized during the bounded check. Live behavior should additionally be verified through `quickshell list --all`, compositor layers, and a compositor screenshot when changing lifecycle or rendering behavior.

## Repository hygiene

Historical backups, Python caches, screenshots, logs, and verification captures are intentionally excluded from version control. Live QML, JavaScript, shell/Python controllers, shader sources, compiled runtime assets, and test sources remain tracked.
