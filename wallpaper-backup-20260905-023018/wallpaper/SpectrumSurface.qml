import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: visualizer

    required property var outputScreen
    required property var spectrum
    screen: outputScreen
    color: "transparent"
    visible: spectrum.length === 1280

    readonly property int animationFps: 24
    property real timePhase: 0.0

    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "quickshell:hk47-spectrum"
    focusable: false
    exclusionMode: ExclusionMode.Ignore
    exclusiveZone: 0
    mask: Region {}

    anchors {
        left: true
        right: true
        top: true
        bottom: true
    }

    Timer {
        id: frameClock
        interval: Math.round(1000 / visualizer.animationFps)
        repeat: true
        running: visualizer.visible
        onTriggered: visualizer.timePhase += 1.0 / visualizer.animationFps
    }

    ShaderEffect {
        anchors.fill: parent
        fragmentShader: Qt.resolvedUrl("spectrum.frag.qsb")

        // The helper supplies one 1280-bin spectrum. Qt uploads it as one
        // uniform block; the fragment shader expands bins across monitor pixels.
        property var spectrum: visualizer.spectrum
        property real timePhase: visualizer.timePhase
        property real levelScale: 1.0
        property real heightLimit: 0.5
        property real binCount: 1280.0
    }
}
