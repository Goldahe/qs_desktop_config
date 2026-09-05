import QtQuick
import Quickshell
import Quickshell.Io
import HkSpectrum.Native 1.0 as Native
import "Theme.js" as Theme

QtObject {
    id: reader
    property Native.SpectrumModel model: Native.SpectrumModel {}
    readonly property int binCount: model.binCount
    readonly property int frames: model.frames
    readonly property int rejected: model.rejected
    readonly property real lastFrame: model.lastFrame
    readonly property real peak: model.peak
    function consume(line) {
        model.consume(line)
    }
    property Process process: Process {
        command: ["bash", Qt.resolvedUrl("capture.sh").toString().replace("file://", "")]
        environment: ({SPECTRUM_FRAME_RATE: String(Theme.frameRate)})
        running: true
        stdout: SplitParser { onRead: data => reader.consume(data) }
        stderr: SplitParser { onRead: data => console.warn("Audio capture: " + data) }
        onExited: { reader.model.clear(); restart.start() }
    }
    property Timer restart: Timer {
        interval: 2000
        onTriggered: reader.process.running = true
    }
    property Timer watchdog: Timer {
        interval: 500; running: true; repeat: true
        onTriggered: if (Date.now() - reader.lastFrame > 1000 && reader.peak > 0) {
            reader.model.clear()
        }
    }
}
