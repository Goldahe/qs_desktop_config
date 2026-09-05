Quickshell audio-reactive wallpaper and spectrum bars

START
  bash /home/hawk/.config/quickshell/wallpaper-spectrum/start.sh
  Always use start.sh. It builds changed native components atomically, refuses a
  duplicate profile, pins rendering to AMD, prevents NVIDIA vendor probing, and
  replaces the former standalone wallpaper profile with this integrated surface.
STOP
  quickshell kill -p /home/hawk/.config/quickshell/wallpaper-spectrum
STATUS
  quickshell ipc -p /home/hawk/.config/quickshell/wallpaper-spectrum call spectrum status
RECONNECT AFTER CHANGING DEFAULT AUDIO OUTPUT
  quickshell ipc -p /home/hawk/.config/quickshell/wallpaper-spectrum call spectrum reconnect

THEME
  Edit Theme.js: wallpaper source/fit settings, heightFraction, gain, opacity,
  hueOffset, and frameRate.
  Maximum bar height defaults to half the monitor. Quickshell reloads JS changes.
  Stripe geometry is deliberately fixed by the requested 640-bin contract.
  wallpaperColorEffectEnabled exposes the future toggle. When false, its Loader
  destroys the native full-screen effect item and the ordinary Image/VideoOutput
  path is used; the color effect has no hidden shader, texture upload, or redraw
  cost. Spectrum bars remain an independent enabled feature.
  wallpaperColorEffectIdleDelayMs defaults to 15000 and
  wallpaperColorEffectFadeDurationMs defaults to 2000.
  wallpaperHueBinCount defaults to 180. It affects only wallpaper recoloring;
  the bars and analyzer retain their full 640-bin contract.

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

WALLPAPER COLOR EFFECT
  WallpaperSurface.qml and Native.WallpaperSpectrum replace the ordinary still
  image draw while wallpaperColorEffectEnabled is true. The still image is
  decoded and composited once per output, then uploaded as one static texture.
  Each changed 640-bin spectrum frame becomes one 640x1 RGBA amplitude texture.
  One full-screen material samples the wallpaper and one amplitude value per
  pixel; there is no CPU recoloring, per-color loop, Canvas, screen capture, or
  second wallpaper copy.

  The fragment shader derives each source pixel's HSV hue, rotates it by
  Theme.hueOffset, maps the complete hue cycle across wallpaper bins 0..179 and
  then back through 179..0, and fetches that amplitude. This deliberately uses
  the more active low-frequency region while preserving all 360 hue positions.
  It calculates luminance and
  mixes grayscale toward the original RGB by the configured logarithmic amplitude
  response, x * 4 with x equal to the sampled amplitude, weighted by saturation confidence and capped at full
  color by the final strength clamp. Both outputs use the same 180 unique
  wallpaper bins and their mirror; the existing 640x1 amplitude texture remains
  shared and unchanged. Amplitude texture updates are capped by the existing
  24 Hz analyzer/renderer cadence.

  The effect begins in normal-color state. Audible input activates it immediately.
  After input remains below the audio threshold for 15 seconds, it fades from the
  grayscale/reactive result back to the unmodified wallpaper over 2 seconds at
  the configured frame rate, then stops requesting wallpaper updates. New audio
  during the hold or fade restores full effect immediately.

  Video wallpapers retain the existing lazy AMD VA-API VideoOutput path and
  currently bypass hue recoloring. Disabling the exposed effect toggle preserves
  image or video format without instantiating the still-image effect material.

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
    DP-1 presentation with wallpaper effect: 23.98 FPS; p95/max 55 ms.
    HDMI-A-1 presentation with wallpaper effect: 23.98 FPS; p95/max 55 ms.
    Active CPU: Quickshell 5.67%, analyzer 0.21%, capture 0.32%; 6.20% combined.
    Silent normal-state CPU: 0.75% combined in this run.
    Active audio changed the complete wallpaper through hue-dependent color and
    retained the spectrum bars. Silence held the grayscale state for 15 seconds,
    faded to normal over 2 seconds, then matched startup pixel-for-pixel.
    The disabled-toggle probe reported enabled=false/amount=0 and rendered the
    ordinary full-color wallpaper with no native effect item instantiated.
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
  The wallpaper-only 180-bin mirrored hue mapping passed the native mapping,
  analyzer, process-lifecycle, visual, and isolated active/silent checks. Two
  180-bin runs presented at 24.01 and 24.02 FPS on both monitors with p95/max
  54/55 ms, zero rejected frames, and 1.50%/1.00% silent CPU. Active combined
  CPU samples were 10.98% and 11.11%; a temporary 640-bin A/B control presented
  identically at 24.01 FPS and sampled 8.65% active/1.25% idle. The shader and
  CPU-side execution paths are unchanged apart from the bin-count value, so the
  CPU difference is recorded as environment/run variance rather than attributed
  to the hue mapping. The requested 180-bin setting was restored afterward.
  Qt frameSwapped timing measures submitted/presented Qt frames, not a hardware
  scanout guarantee. Evidence is in verification/results.json and PNG files.

GPU RESTRICTION
  NVIDIA is reserved for VFIO and explicitly approved AI workloads. This profile
  selects the AMD RX 7800 XT through Mesa EGL/Vulkan and hides CUDA devices.
  Verify with /proc/<pid>/fd after renderer changes; intent variables are not proof.

BACKUP
  Before wallpaper-only 180-bin hue mapping:
    backups/wallpaper-hue-180-bins-20260905-203000/
  Verified integrated color effect: backups/color-wallpaper-effect-20260905-194915/
  Before native binary transport: backups/before-native-binary-20260905-160036/
  Pre-640 profile: backups/640-bins-20260905-031146/
  Earlier complete profiles: ../wallpaper-backup-20260905-023018/
