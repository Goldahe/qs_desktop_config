import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Wayland
import "Theme.js" as Theme
import HkSpectrum.Native 1.0 as Native

PanelWindow {
    id: visualizer
    required property var outputScreen
    required property var spectrumModel
    property bool measuring: false
    signal presented(string name, double stamp)
    screen: outputScreen
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.namespace: "quickshell:hk47-spectrum"
    focusable: false
    exclusionMode: ExclusionMode.Ignore
    exclusiveZone: 0
    mask: Region {}
    anchors { left: true; right: true; bottom: true }
    implicitHeight: Math.round(outputScreen.height * Math.max(0.05, Math.min(1, Theme.heightFraction)))

    Connections {
        target: visualizer.contentItem.Window.window
        function onFrameSwapped() {
            if (visualizer.measuring) visualizer.presented(visualizer.outputScreen.name, Date.now())
        }
    }

    Native.SpectrumBars {
        anchors.fill: parent
        model: visualizer.spectrumModel
        gain: Theme.gain
        effectOpacity: Math.max(0, Math.min(1, Theme.opacity))
        hueOffset: Theme.hueOffset
    }
}
