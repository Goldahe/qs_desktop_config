import QtQuick
import Quickshell
import Quickshell.Wayland

// Smooth, click-through holographic projection from the taskbar to the avatar.
PanelWindow {
    id: beam

    required property var avatar
    readonly property int taskbarHeight: 38
    readonly property int avatarSize: 256
    readonly property real screenWidth: screen ? screen.width : 2560
    readonly property real screenHeight: screen ? screen.height : 1440
    readonly property real avatarCenterY: screenHeight * 0.75
    readonly property int animationFps: avatar.animationFps
    // Start three pixels above the taskbar's top edge.
    readonly property real emitterY: screenHeight - taskbarHeight - 3
    // Terminate one fifth of the avatar height upward from its bottom edge.
    readonly property real targetY: avatarCenterY + avatarSize / 2 - avatarSize / 5
    readonly property real sourceRadius: 3
    readonly property real outerTargetHalf: avatarSize / 2
    readonly property real innerTargetHalf: avatarSize / 4

    visible: avatar.active || avatar.activationLevel > 0.001
    color: "transparent"

    // Keep the projection behind the avatar's overlay-layer surface.
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "quickshell:hk47-avatar-beam"
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

    Image {
        id: crtImage
        visible: false
        width: 256
        height: 256
        source: "file:///games/Windows/VM-Share/ClipStudio_Project/HK-47_CRT_effect.png"
        sourceSize.width: 256
        sourceSize.height: 256
        smooth: false
        mipmap: false
        cache: true
        asynchronous: true
    }

    ShaderEffect {
        anchors.fill: parent
        opacity: Math.max(0.0, Math.min(1.0, beam.avatar.activationLevel))
        fragmentShader: Qt.resolvedUrl("shaders/hologram-beam.frag.qsb")

        property var crtTexture: crtImage
        property real screenWidth: beam.screenWidth
        property real screenHeight: beam.screenHeight
        property real sourceY: beam.emitterY
        property real targetY: beam.targetY
        property real sourceRadius: beam.sourceRadius
        property real outerTargetHalf: beam.outerTargetHalf
        property real innerTargetHalf: beam.innerTargetHalf
        // These inputs are advanced exclusively by AvatarPortrait's 24 Hz clock;
        // the beam owns no timer and cannot request a faster animation cadence.
        property real audioAmplitude: beam.avatar.audioAmplitude
        property real scanPhase: beam.avatar.scanPhase
        property color beamColor: beam.avatar.renderedShineColor
    }
}
