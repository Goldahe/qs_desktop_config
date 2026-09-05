import QtQml
import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: reader
    property var spectrum: []
    property var packedSpectrum: [Qt.vector4d(0, 0, 0, 0), Qt.vector4d(0, 0, 0, 0), Qt.vector4d(0, 0, 0, 0), Qt.vector4d(0, 0, 0, 0), Qt.vector4d(0, 0, 0, 0), Qt.vector4d(0, 0, 0, 0), Qt.vector4d(0, 0, 0, 0), Qt.vector4d(0, 0, 0, 0), Qt.vector4d(0, 0, 0, 0), Qt.vector4d(0, 0, 0, 0), Qt.vector4d(0, 0, 0, 0)]
    readonly property int binCount: 44

    function consume(line) {
        const values = line.trim().split(",")
        if (values.length !== reader.binCount)
            return
        const next = new Array(reader.binCount)
        const packed = []
        for (let i = 0; i < reader.binCount; ++i) {
            const value = Number(values[i])
            next[i] = Number.isFinite(value) ? Math.max(0.0, Math.min(1.0, value)) : 0.0
        }
        // vec4 packing matches the shader's std140 layout and keeps the
        // per-frame upload to eleven compact GPU vectors.
        for (let i = 0; i < 11; ++i) {
            const base = i * 4
            packed.push(Qt.vector4d(next[base] || 0.0,
                                    next[base + 1] || 0.0,
                                    next[base + 2] || 0.0,
                                    next[base + 3] || 0.0))
        }
        reader.spectrum = next
        reader.packedSpectrum = packed
    }

    property Process fftProcess: Process {
        command: ["/home/hawk/.config/quickshell/wallpaper-spectrum/fft-spectrum"]
        running: true

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => reader.consume(data)
        }
    }
}
