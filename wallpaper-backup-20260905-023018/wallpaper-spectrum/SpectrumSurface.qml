import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: visualizer
    required property var outputScreen
    required property var spectrum
    screen: outputScreen
    color: "transparent"
    visible: true

    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.namespace: "quickshell:hk47-spectrum"
    focusable: false
    exclusionMode: ExclusionMode.Ignore
    exclusiveZone: 0
    mask: Region {}
    anchors { left: true; right: true; top: true; bottom: true }

    ShaderEffect {
        anchors.fill: parent
        fragmentShader: Qt.resolvedUrl("spectrum.frag.qsb")
        property real s0: visualizer.spectrum[0] || 0.0
        property real s1: visualizer.spectrum[1] || 0.0
        property real s2: visualizer.spectrum[2] || 0.0
        property real s3: visualizer.spectrum[3] || 0.0
        property real s4: visualizer.spectrum[4] || 0.0
        property real s5: visualizer.spectrum[5] || 0.0
        property real s6: visualizer.spectrum[6] || 0.0
        property real s7: visualizer.spectrum[7] || 0.0
        property real s8: visualizer.spectrum[8] || 0.0
        property real s9: visualizer.spectrum[9] || 0.0
        property real s10: visualizer.spectrum[10] || 0.0
        property real s11: visualizer.spectrum[11] || 0.0
        property real s12: visualizer.spectrum[12] || 0.0
        property real s13: visualizer.spectrum[13] || 0.0
        property real s14: visualizer.spectrum[14] || 0.0
        property real s15: visualizer.spectrum[15] || 0.0
        property real s16: visualizer.spectrum[16] || 0.0
        property real s17: visualizer.spectrum[17] || 0.0
        property real s18: visualizer.spectrum[18] || 0.0
        property real s19: visualizer.spectrum[19] || 0.0
        property real s20: visualizer.spectrum[20] || 0.0
        property real s21: visualizer.spectrum[21] || 0.0
        property real s22: visualizer.spectrum[22] || 0.0
        property real s23: visualizer.spectrum[23] || 0.0
        property real s24: visualizer.spectrum[24] || 0.0
        property real s25: visualizer.spectrum[25] || 0.0
        property real s26: visualizer.spectrum[26] || 0.0
        property real s27: visualizer.spectrum[27] || 0.0
        property real s28: visualizer.spectrum[28] || 0.0
        property real s29: visualizer.spectrum[29] || 0.0
        property real s30: visualizer.spectrum[30] || 0.0
        property real s31: visualizer.spectrum[31] || 0.0
        property real s32: visualizer.spectrum[32] || 0.0
        property real s33: visualizer.spectrum[33] || 0.0
        property real s34: visualizer.spectrum[34] || 0.0
        property real s35: visualizer.spectrum[35] || 0.0
        property real s36: visualizer.spectrum[36] || 0.0
        property real s37: visualizer.spectrum[37] || 0.0
        property real s38: visualizer.spectrum[38] || 0.0
        property real s39: visualizer.spectrum[39] || 0.0
        property real s40: visualizer.spectrum[40] || 0.0
        property real s41: visualizer.spectrum[41] || 0.0
        property real s42: visualizer.spectrum[42] || 0.0
        property real s43: visualizer.spectrum[43] || 0.0
        property real screenWidth: visualizer.width
        property real screenHeight: visualizer.height
        property real binCount: 44.0
    }
}
