#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"

# Compile Qt shader binaries from the tracked shader sources when they are
# missing or stale. Keep the generated files out of Git while making this
# profile self-contained when launched on a fresh checkout.
for shader in shaders/avatar-shine.frag shaders/hologram-beam.frag; do
    output="$shader.qsb"
    if [[ ! -f $output || $shader -nt $output ]]; then
        /usr/lib/qt6/bin/qsb --glsl 100es,120,150 --hlsl 50 --msl 12 \
            -o "$output.new" "$shader"
        mv -f "$output.new" "$output"
    fi
done

# The RTX 2080 is reserved for VFIO and explicitly approved AI workloads.
# Keep the avatar's ordinary desktop rendering on the AMD GPU.
unset __NV_PRIME_RENDER_OFFLOAD __NV_PRIME_RENDER_OFFLOAD_PROVIDER
unset __GLX_VENDOR_LIBRARY_NAME VK_ICD_FILENAMES
export DRI_PRIME=pci-0000_03_00_0
export MESA_VK_DEVICE_SELECT=1002:747e
export VK_DRIVER_FILES=/usr/share/vulkan/icd.d/radeon_icd.json
export __EGL_VENDOR_LIBRARY_FILENAMES=/usr/share/glvnd/egl_vendor.d/50_mesa.json
export CUDA_VISIBLE_DEVICES=""

exec quickshell --no-duplicate --daemonize -p "$PWD/shell.qml"
