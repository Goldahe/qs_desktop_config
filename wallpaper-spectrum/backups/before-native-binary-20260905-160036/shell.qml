import QtQuick
import Quickshell
import Quickshell.Io
import "Theme.js" as Theme

ShellRoot {
    id: root
    property bool measuring: false
    property var timings: ({})
    SpectrumReader { id: audio }
    Variants {
        model: Quickshell.screens
        SpectrumSurface {
            required property var modelData
            outputScreen: modelData
            spectrumModel: audio.model
            measuring: root.measuring
            onPresented: (name, stamp) => {
                if (!root.timings[name]) root.timings[name] = []
                if (root.timings[name].length < 3600) root.timings[name].push(stamp)
            }
        }
    }
    IpcHandler {
        target: "spectrum"
        function status(): string {
            return JSON.stringify({bins: audio.binCount, frameRate: Theme.frameRate,
                frames: audio.frames, rejected: audio.rejected,
                peak: audio.peak, ageMs: Date.now()-audio.lastFrame,
                running: audio.process.running})
        }
        function measure(): void { root.timings = ({}); root.measuring = true }
        function results(): string {
            root.measuring = false
            return JSON.stringify(root.timings)
        }
        function reconnect(): void { audio.process.running = false }
    }
}
