HK-47 Quickshell Wallpaper

Profile:
  /home/hawk/.config/quickshell/wallpaper/shell.qml

Start:
  bash /home/hawk/.config/quickshell/wallpaper/start.sh

Always use start.sh. It pins rendering and QtMultimedia video decode to the AMD
GPU. The NVIDIA GPU is reserved for VFIO and explicitly approved AI workloads.

Change wallpaper:
  Edit Theme.js and change wallpaperSource. The profile is automatically
  classified by extension when sourceType is "auto".

Supported dispatch:
  Images: PNG, JPG/JPEG, WEBP, AVIF, GIF, BMP, SVG (Qt image backend permitting)
  Video containers: MP4, M4V, MKV, WebM, MOV, AVI, WMV, TS, M2TS
  H.264/H.265 are codecs, not file formats; playback depends on the installed
  QtMultimedia/FFmpeg decoder and the container.

Theme controls in Theme.js:
  sourceType     auto, image, or video
  fitMode        crop, fit, or stretch
  imageOpacity   wallpaper opacity
  dimOpacity     dark overlay amount
  dimColor       overlay color
  mirror         horizontal flip
  loopVideo      loop video playback
  autoPlay       start video immediately
  playbackRate   video speed

The surface is per-monitor, click-through, non-exclusive, and placed on the
Wayland background layer. It does not modify the existing bar or avatar profile.

Audio-reactive bars are maintained separately in ../wallpaper-spectrum.
Start them with bash ../wallpaper-spectrum/start.sh; appearance settings are in
../wallpaper-spectrum/Theme.js. Theme.js in this wallpaper directory is the
only wallpaper theme configuration; the unused Theme.qml and old duplicate
spectrum sources were archived in ../wallpaper-backup-20260905-023018.
