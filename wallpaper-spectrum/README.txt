Quickshell audio-reactive wallpaper bars

START
  bash /home/hawk/.config/quickshell/wallpaper-spectrum/start.sh
  Always use start.sh. It builds changed native components atomically, refuses a
  duplicate profile, pins rendering to AMD, and prevents NVIDIA vendor probing.
STOP
  quickshell kill -p /home/hawk/.config/quickshell/wallpaper-spectrum
STATUS
  quickshell ipc -p /home/hawk/.config/quickshell/wallpaper-spectrum call spectrum status
RECONNECT AFTER CHANGING DEFAULT AUDIO OUTPUT
  quickshell ipc -p /home/hawk/.config/quickshell/wallpaper-spectrum call spectrum reconnect

THEME
  Edit Theme.js: heightFraction, gain, opacity, hueOffset.
  Maximum bar height defaults to half the monitor. Quickshell reloads JS changes.
  Stripe geometry is deliberately fixed by the requested 640-bin contract.

AUDIO AND GEOMETRY
  capture.sh captures the exact default sink .monitor as float32 stereo at
  48000 Hz with requested 16 ms latency. SPECTRUM_SINK can override the sink.
  fft-spectrum uses a 1280-sample Hann FFT through FFTW and a frame-rate-derived
  hop: at the default 24 Hz this is 2000 samples per update. A real 1280-point
  FFT has 641 unique bins including Nyquist;
  it emits the first 640 as one fixed 2560-byte little-endian float32 frame,
  bins 0..639, spanning 0 through 23962.5 Hz at 37.5 Hz
  spacing. The Nyquist bin 640 is deliberately omitted. Mapping uses a fixed
  amplitude reference, -80 dBFS floor, 20 ms attack and 140 ms release.
  No per-frame normalization is used, so volume controls height.

  The 2560-pixel monitor displays 1280 one-physical-pixel stripes: 640 unique
  bins on each half. Frequency orientation is edge-to-center on both sides:
  bin 0 (lowest frequency) starts at the far left edge and far right edge;
  bin 639 is adjacent to the center on each side. There is exactly one empty
  pixel between bars.
  Each stripe maps to exactly one bin; there is no neighboring-bin interpolation
  and no top-edge anti-aliasing. On the 1920-pixel output the renderer uses 480
  bins and 960 total stripes, again one physical pixel per bar with one gap per
  bar. The 640-bin analyzer continues to provide the source frame; the smaller
  output deliberately consumes only its first 480 bins.

RENDERER
  native/SpectrumBarsPlugin.cpp provides a shared SpectrumModel that owns and
  supervises the capture QProcess, buffers arbitrary stdout chunks, validates
  exact 640-float binary frames, and copies each valid frame into one fixed array.
  Both monitor renderers read that model directly. QML no longer owns the process,
  splits lines, parses decimal strings, builds JavaScript arrays, or converts a
  QVariantList separately for each monitor. The native lifecycle preserves
  restart, reconnect, watchdog clearing, diagnostics, and child cleanup.

  The plugin also builds one dynamic Qt scene-graph geometry node per monitor:
  1280 quads, 5120 vertices, one vertex-color material. It does not
  create 1280 QML delegates, upload a full-screen Canvas, or use scalar/array
  shader uniforms. Colors are cached until theme color/opacity changes; incoming
  frames update only cached amplitudes and geometry. The external QML module is
  qml/HkSpectrum/Native and must remain on QML_IMPORT_PATH via start.sh.
  The transparency gradient is fixed to screen position: the top of the spectrum
  surface (the monitor's vertical midpoint at the default heightFraction) is zero
  alpha and the monitor bottom is 80% of Theme.opacity. Each bar's top vertices
  receive the opacity appropriate to their actual vertical position, so shorter
  bars do not restart the gradient at zero. QSG interpolates the premultiplied
  vertex colors inside each existing quad, adding no geometry, texture, shader
  pass, delegate, or draw call.

  Panel surfaces are click-through, non-exclusive, on WlrLayer.Bottom, and occupy
  only the configured maximum height. They remain behind windows, bar, and avatar.

VERIFICATION
  python test_fft.py
  python test_render.py
  python test_native_process.py
  python test_live.py
  Stop the live spectrum before test_live.py. It creates an isolated null sink,
  never changes the default sink, and cleans up all processes and modules.

  Latest isolated end-to-end result:
    Analyzer tests: 10/10 pass, including ASan and UBSan in the analyzer run.
    Native contract: binary parsing, process lifecycle, 640 unique bins, and
    exact width-dependent stripe coordinates pass.
    Configured frame rate: 24 Hz; direct 48 kHz input test: 24 frames/sec.
    DP-1 presentation: 24.00 FPS; p95 53 ms; maximum 54 ms.
    HDMI-A-1 presentation: 24.00 FPS; p95 53 ms; maximum 54 ms.
    Native-binary active CPU: Quickshell 5.84%, analyzer 0.42%, capture 0.63%.
    Combined native-binary CPU: 6.89% active and 1.50% silent idle.
    Audio screenshot changed only the active lower bar area; released silence
    returned pixel-for-pixel to the initial static wallpaper.
  After unchanged-frame suppression and adaptive scheduling, the live benchmark
  measured 3.00% combined CPU while silent and 7.40% combined while active.
  Active usage is 13.2% lower than the prior 8.53% baseline; the idle renderer
  no longer receives redundant geometry notifications. Decay notifications are
  limited to an 8 Hz maximum, while active audio remains at 24 Hz.
  Native binary transport reduced active CPU from 7.40% to 6.89% (6.9%) and
  silent idle from 3.00% to 1.50% (50.0%) in the isolated benchmark.
  With the native vertical transparency gradient enabled, the next isolated run
  measured 5.62% active and 1.25% silent idle. These lower values show no
  measurable gradient penalty, but ordinary run-to-run variance means they are
  not attributed to the gradient as an optimization. Presentation was 24.02 FPS
  on both monitors with zero rejected frames.
  Qt frameSwapped timing measures submitted/presented Qt frames, not a hardware
  scanout guarantee. Evidence is in verification/results.json and PNG files.

GPU RESTRICTION
  NVIDIA is reserved for VFIO and explicitly approved AI workloads. This profile
  selects the AMD RX 7800 XT through Mesa EGL/Vulkan and hides CUDA devices.
  Verify with /proc/<pid>/fd after renderer changes; intent variables are not proof.

BACKUP
  Before native binary transport: backups/before-native-binary-20260905-160036/
  Pre-640 profile: backups/640-bins-20260905-031146/
  Earlier complete profiles: ../wallpaper-backup-20260905-023018/
