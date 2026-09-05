Quickshell audio-reactive wallpaper bars

Authoritative implementation: this directory. Wallpaper images/video remain in
../wallpaper, unchanged. Old duplicate spectrum implementations were archived.

START (builds changed C++/GLSL first; refuses duplicate instance)
  bash /home/hawk/.config/quickshell/wallpaper-spectrum/start.sh
  Always use start.sh: it pins this decorative renderer to AMD. The NVIDIA GPU
  is reserved for VFIO and explicitly approved AI workloads.
STOP
  quickshell kill -p /home/hawk/.config/quickshell/wallpaper-spectrum
STATUS
  quickshell ipc -p /home/hawk/.config/quickshell/wallpaper-spectrum call spectrum status
RECONNECT after changing default playback output
  quickshell ipc -p /home/hawk/.config/quickshell/wallpaper-spectrum call spectrum reconnect

THEMES
  Edit Theme.js: heightFraction, gain, barWidth, gapWidth, opacity, hueOffset.
  Default maximum height: half the monitor. Width/gap are physical pixels.
  Quickshell watches QML/JS changes. Shader/C++ changes require stop/start.sh.
  Wallpaper artwork and video settings: ../wallpaper/Theme.js.
  No new Hyprland autostart entry or user service was installed.

DATA PATH
  capture.sh supervises parec and fft-spectrum, cleans both up on termination.
  Captures the current default sink's exact .monitor, never the microphone.
  SPECTRUM_SINK can override the sink name at launch; default is queried on each
  capture restart. Changing output during a session requires RECONNECT above.
  Capture: float32 stereo 48000 Hz, requested 16 ms latency.
  Analyzer: 4096-sample Hann FFT, precomputed twiddles/window/index permutation,
  reused buffers, 800-sample hops = 60 spectral updates/second.
  44 bins span DC to 503.90625 Hz (the FFT bins below 512 Hz).
  Fixed amplitude mapping, -80 dBFS floor, 20 ms attack and 140 ms release.
  No per-frame peak normalization: volume changes affect height.
  Reader validates 44 finite numbers; reports rejected frames and stream age.
  Failed capture restarts after 2 seconds; stale bars clear after 1 second.
  GPU: one ShaderEffect per output, explicit scalar uniforms, interpolated bins,
  mirrored bass-center layout, transparent gaps and strictly bounded bar height.
  Bottom layer, click-through, non-exclusive, below normal windows and panels.
  Idle audio does not force needless frame rendering. Render cadence during
  changing audio is driven by incoming 60 Hz data and compositor presentation.

REGRESSION TESTS
  python test_fft.py
  python test_render.py
  python test_live.py
  Run from this directory; stop the live spectrum before test_live.py.
  test_render.py briefly opens a test window and reads real GPU-rendered pixels.
  test_live.py temporarily creates an isolated null sink, does not change the
  default output and does not play audible test tones. It checks the HDMI-A-1
  wallpaper screenshot (must be unobscured), release-to-silence, accepted frames,
  actual Qt frameSwapped timing on both outputs and /proc CPU intervals.
  The test assumes the present two-monitor setup and static wallpaper.
  Acceptance: 58-62 average rendered FPS, <=35 ms p95 interval, no invalid frames,
  changed lower-half pixels during audio, exact original pixels after silence.
  Qt frameSwapped timing measures submitted/presented Qt frames, not a hardware
  scanout guarantee. Rendering load and compositor scheduling can add jitter.
  verification/results.json and PNGs contain the latest measured results.

BACKUP
  /home/hawk/.config/quickshell/wallpaper-backup-20260905-023018
  Contains complete original wallpaper and spectrum profiles.
