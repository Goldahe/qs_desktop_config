import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: reader
    property var spectrum: Array(44).fill(0)
    property int frames: 0
    property int rejected: 0
    property real lastFrame: 0
    property real peak: 0
    function consume(line) {
        const parts = line.trim().split(",")
        if (parts.length !== 44) { rejected++; return }
        let next = new Array(44)
        let peak = 0
        for (let i = 0; i < 44; ++i) {
            const n = Number(parts[i])
            if (!Number.isFinite(n)) { rejected++; return }
            next[i] = Math.max(0, Math.min(1, n))
            peak = Math.max(peak, next[i])
        }
        reader.peak = peak
        spectrum = next
        frames++
        lastFrame = Date.now()
    }
    property Process process: Process {
        command: ["bash", Qt.resolvedUrl("capture.sh").toString().replace("file://", "")]
        running: true
        stdout: SplitParser { onRead: data => reader.consume(data) }
        stderr: SplitParser { onRead: data => console.warn("Audio capture: " + data) }
        onExited: { reader.spectrum = Array(44).fill(0); restart.start() }
    }
    property Timer restart: Timer {
        interval: 2000
        onTriggered: reader.process.running = true
    }
    // Clear stale bars if the stream stalls; never retain a false live signal.
    property Timer watchdog: Timer {
        interval: 500; running: true; repeat: true
        onTriggered: if (Date.now() - reader.lastFrame > 1000 && reader.peak > 0) {
            reader.spectrum = Array(44).fill(0); reader.peak = 0
        }
    }
}
