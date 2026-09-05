import Quickshell
import Quickshell.Io

QtObject {
    id: reader
    property var spectrum: []
    readonly property int binCount: 1280

    function consume(line) {
        const values = line.trim().split(",")
        if (values.length !== reader.binCount)
            return
        const next = new Array(reader.binCount)
        for (let i = 0; i < reader.binCount; ++i) {
            const value = Number(values[i])
            next[i] = Number.isFinite(value) ? Math.max(0.0, Math.min(1.0, value)) : 0.0
        }
        reader.spectrum = next
    }

    Process {
        id: fftProcess
        command: ["/home/hawk/.config/quickshell/wallpaper/fft-spectrum"]
        running: true

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => reader.consume(data)
        }
    }
}
