#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
# Keep analyzer, shaders, resources, and native renderer artifacts synchronized.
if [[ ! -x fft-spectrum || fft-spectrum.cpp -nt fft-spectrum ]]; then
    g++ -O3 -std=c++17 -Wall -Wextra -pedantic fft-spectrum.cpp -o fft-spectrum.new $(pkg-config --cflags --libs fftw3f)
    mv -f fft-spectrum.new fft-spectrum
fi
for stage in vert frag; do
    source="native/shaders/wallpaper.$stage"
    output="$source.qsb"
    if [[ ! -f $output || $source -nt $output ]]; then
        /usr/lib/qt6/bin/qsb --glsl 100es,120,150 --hlsl 50 --msl 12 -o "$output.new" "$source"
        mv -f "$output.new" "$output"
    fi
done
if [[ ! -f native/HkSpectrumShaders.cpp || native/HkSpectrumShaders.qrc -nt native/HkSpectrumShaders.cpp || native/shaders/wallpaper.vert.qsb -nt native/HkSpectrumShaders.cpp || native/shaders/wallpaper.frag.qsb -nt native/HkSpectrumShaders.cpp ]]; then
    /usr/lib/qt6/rcc native/HkSpectrumShaders.qrc -o native/HkSpectrumShaders.cpp.new
    mv -f native/HkSpectrumShaders.cpp.new native/HkSpectrumShaders.cpp
fi
if [[ ! -f qml/HkSpectrum/Native/libhkspectrumplugin.so || native/SpectrumBarsPlugin.cpp -nt qml/HkSpectrum/Native/libhkspectrumplugin.so || native/HkSpectrumShaders.cpp -nt qml/HkSpectrum/Native/libhkspectrumplugin.so ]]; then
    /usr/lib/qt6/moc native/SpectrumBarsPlugin.cpp -o native/SpectrumBarsPlugin.moc
    g++ -O3 -std=c++17 -fPIC -shared native/SpectrumBarsPlugin.cpp native/HkSpectrumShaders.cpp \
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
export LIBVA_DRIVER_NAME=radeonsi
export QT_FFMPEG_DECODING_HW_DEVICE_TYPES=vaapi
export QT_FFMPEG_ENCODING_HW_DEVICE_TYPES=vaapi
export CUDA_VISIBLE_DEVICES=""
export QML_IMPORT_PATH="$PWD/qml${QML_IMPORT_PATH:+:$QML_IMPORT_PATH}"
# This profile now owns both the background wallpaper and spectrum surfaces.
quickshell kill -p "$PWD/../wallpaper" >/dev/null 2>&1 || true
exec quickshell --no-duplicate --daemonize -p "$PWD/shell.qml"
