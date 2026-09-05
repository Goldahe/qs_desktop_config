HK-47 Audio Spectrum Overlay

Profile:
  /home/hawk/.config/quickshell/wallpaper-spectrum/shell.qml

Start:
  quickshell -p /home/hawk/.config/quickshell/wallpaper-spectrum/shell.qml

Architecture:
  fft-spectrum captures the current default PipeWire sink monitor, computes a
  4096-point Hann-windowed FFT, and emits 1280 normalized bins at approximately
  60 Hz. Quickshell reads one line per frame. Each monitor renders up to 1280
  bars across its width, mapping those bars to the 1280 bins.
  Bars originate at the bottom and are capped at half the monitor height.

Appearance:
  Hue sweeps continuously from left to right across the full RGB spectrum.
  The overlay is click-through, non-exclusive, per-monitor, and sits directly
  above the wallpaper on the bottom layer, behind the taskbar, avatar, and normal windows.

Notes:
  The renderer deliberately uses a reduced set of transparent QML rectangles instead of a large
  shader uniform array. Qt's uniform-array ABI produced an opaque full-screen
  field on this Quickshell/Qt combination; the corrected renderer is reliable.
  The visual timer and FFT producer run at 60 Hz. The helper follows the
  default sink selected by pactl at startup. If the default sink changes,
  restart this profile to retarget its monitor.
