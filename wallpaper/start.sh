#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"

# The RTX 2080 is reserved for VFIO and explicitly approved AI workloads.
# Keep wallpaper rendering and QtMultimedia hardware probing on the AMD GPU.
unset __NV_PRIME_RENDER_OFFLOAD __NV_PRIME_RENDER_OFFLOAD_PROVIDER
unset __GLX_VENDOR_LIBRARY_NAME VK_ICD_FILENAMES
export DRI_PRIME=pci-0000_03_00_0
export MESA_VK_DEVICE_SELECT=1002:747e
export VK_DRIVER_FILES=/usr/share/vulkan/icd.d/radeon_icd.json
export __EGL_VENDOR_LIBRARY_FILENAMES=/usr/share/glvnd/egl_vendor.d/50_mesa.json
export LIBVA_DRIVER_NAME=radeonsi
export QT_FFMPEG_DECODING_HW_DEVICE_TYPES=vaapi
export QT_FFMPEG_ENCODING_HW_DEVICE_TYPES=vaapi
export CUDA_VISIBLE_DEVICES=""

exec quickshell --no-duplicate --daemonize -p "$PWD/shell.qml"
