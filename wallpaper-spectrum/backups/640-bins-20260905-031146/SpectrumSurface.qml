import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Wayland
import "Theme.js" as Theme

PanelWindow {
    id: visualizer
    required property var outputScreen
    required property var spectrum
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
    ShaderEffect {
        anchors.fill: parent
        fragmentShader: Qt.resolvedUrl("spectrum.frag.qsb")
        property real s0: visualizer.spectrum[0] || 0
        property real s1: visualizer.spectrum[1] || 0
        property real s2: visualizer.spectrum[2] || 0
        property real s3: visualizer.spectrum[3] || 0
        property real s4: visualizer.spectrum[4] || 0
        property real s5: visualizer.spectrum[5] || 0
        property real s6: visualizer.spectrum[6] || 0
        property real s7: visualizer.spectrum[7] || 0
        property real s8: visualizer.spectrum[8] || 0
        property real s9: visualizer.spectrum[9] || 0
        property real s10: visualizer.spectrum[10] || 0
        property real s11: visualizer.spectrum[11] || 0
        property real s12: visualizer.spectrum[12] || 0
        property real s13: visualizer.spectrum[13] || 0
        property real s14: visualizer.spectrum[14] || 0
        property real s15: visualizer.spectrum[15] || 0
        property real s16: visualizer.spectrum[16] || 0
        property real s17: visualizer.spectrum[17] || 0
        property real s18: visualizer.spectrum[18] || 0
        property real s19: visualizer.spectrum[19] || 0
        property real s20: visualizer.spectrum[20] || 0
        property real s21: visualizer.spectrum[21] || 0
        property real s22: visualizer.spectrum[22] || 0
        property real s23: visualizer.spectrum[23] || 0
        property real s24: visualizer.spectrum[24] || 0
        property real s25: visualizer.spectrum[25] || 0
        property real s26: visualizer.spectrum[26] || 0
        property real s27: visualizer.spectrum[27] || 0
        property real s28: visualizer.spectrum[28] || 0
        property real s29: visualizer.spectrum[29] || 0
        property real s30: visualizer.spectrum[30] || 0
        property real s31: visualizer.spectrum[31] || 0
        property real s32: visualizer.spectrum[32] || 0
        property real s33: visualizer.spectrum[33] || 0
        property real s34: visualizer.spectrum[34] || 0
        property real s35: visualizer.spectrum[35] || 0
        property real s36: visualizer.spectrum[36] || 0
        property real s37: visualizer.spectrum[37] || 0
        property real s38: visualizer.spectrum[38] || 0
        property real s39: visualizer.spectrum[39] || 0
        property real s40: visualizer.spectrum[40] || 0
        property real s41: visualizer.spectrum[41] || 0
        property real s42: visualizer.spectrum[42] || 0
        property real s43: visualizer.spectrum[43] || 0
        property real screenWidth: width * visualizer.devicePixelRatio
        property real screenHeight: height * visualizer.devicePixelRatio
        property real gain: Theme.gain
        property real barWidth: Math.max(1, Theme.barWidth)
        property real gapWidth: Math.max(0, Theme.gapWidth)
        property real effectOpacity: Math.max(0, Math.min(1, Theme.opacity))
        property real hueOffset: Theme.hueOffset
    }
}
