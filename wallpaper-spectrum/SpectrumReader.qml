import QtQuick
import HkSpectrum.Native 1.0 as Native
import "Theme.js" as Theme

QtObject {
    id: reader
    readonly property string capturePath: Qt.resolvedUrl("capture.sh").toString().replace("file://", "")
    property Native.SpectrumModel model: Native.SpectrumModel {
        captureCommand: ["bash", reader.capturePath]
        frameRate: Theme.frameRate
        colorEffectEnabled: Theme.wallpaperColorEffectEnabled
        colorEffectIdleDelay: Theme.wallpaperColorEffectIdleDelayMs
        colorEffectFadeDuration: Theme.wallpaperColorEffectFadeDurationMs
        running: true
    }
    readonly property int binCount: model.binCount
    readonly property int frames: model.frames
    readonly property int rejected: model.rejected
    readonly property real lastFrame: model.lastFrame
    readonly property real peak: model.peak
    readonly property bool running: model.running
    function reconnect() {
        model.reconnect()
    }
}
