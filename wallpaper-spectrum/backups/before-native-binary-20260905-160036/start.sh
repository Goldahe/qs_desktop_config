#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
# Keep analyzer and native renderer artifacts in sync with their source files.
if [[ ! -x fft-spectrum || fft-spectrum.cpp -nt fft-spectrum ]]; then
    g++ -O3 -std=c++17 -Wall -Wextra -pedantic fft-spectrum.cpp -o fft-spectrum.new $(pkg-config --cflags --libs fftw3f)
    mv -f fft-spectrum.new fft-spectrum
fi
if [[ ! -f qml/HkSpectrum/Native/libhkspectrumplugin.so || native/SpectrumBarsPlugin.cpp -nt qml/HkSpectrum/Native/libhkspectrumplugin.so ]]; then
    /usr/lib/qt6/moc native/SpectrumBarsPlugin.cpp -o native/SpectrumBarsPlugin.moc
    g++ -O3 -std=c++17 -fPIC -shared native/SpectrumBarsPlugin.cpp \
        -o qml/HkSpectrum/Native/libhkspectrumplugin.so.new $(pkg-config --cflags --libs Qt6Quick Qt6Qml)
    mv -f qml/HkSpectrum/Native/libhkspectrumplugin.so.new qml/HkSpectrum/Native/libhkspectrumplugin.so
fi
# The RTX 2080 is reserved for VFIO and explicitly approved AI workloads.
# Force this decorative renderer onto AMD and prevent NVIDIA vendor probing.
unset __NV_PRIME_RENDER_OFFLOAD __NV_PRIME_RENDER_OFFLOAD_PROVIDER
unset __GLX_VENDOR_LIBRARY_NAME VK_ICD_FILENAMES
export DRI_PRIME=pci-0000_03_00_0
export MESA_VK_DEVICE_SELECT=1002:747e
export VK_DRIVER_FILES=/usr/share/vulkan/icd.d/radeon_icd.json
export __EGL_VENDOR_LIBRARY_FILENAMES=/usr/share/glvnd/egl_vendor.d/50_mesa.json
export CUDA_VISIBLE_DEVICES=""
export QML_IMPORT_PATH="$PWD/qml${QML_IMPORT_PATH:+:$QML_IMPORT_PATH}"
exec quickshell --no-duplicate --daemonize -p "$PWD/shell.qml"
