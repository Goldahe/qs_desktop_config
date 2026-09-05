import QtQuick
import Quickshell
import Quickshell.Wayland

// Static, click-through HK-47 portrait. The window center sits horizontally
// centered and one quarter of the screen height up from the bottom.
PanelWindow {
    id: portrait

    implicitWidth: 256
    implicitHeight: 256
    color: "transparent"

    // Public effect controls. Change shineColor to any Qt color at runtime.
    property color shineColor: "#5bc8ff"
    property real shineStrength: 0.82
    property real hologramOpacity: 0.72
    property real glowStrength: 0.70
    // Source-sized black silhouette behind the holographic portrait.
    property real silhouetteOpacity: 0.78
    property real silhouetteScale: 1.0
    property real silhouetteOffsetY: 0.0
    property real silhouetteFeatherPixels: 4.0
    readonly property real visualAmplitude: audioAmplitude * 0.5
    readonly property real effectiveShineStrength: shineStrength
                                                + (1.0 - shineStrength)
                                                * visualAmplitude
    property bool active: false
    property real activationLevel: 0.0
    property real scanPhase: 0.0
    property real refreshPhase: -0.15
    property real powerFrom: 0.0
    property real powerTo: 0.0
    property real powerStartedAt: 0.0
    property real powerDuration: 600.0
    property bool powerRunning: false
    property real animationEpoch: Date.now()
    readonly property int animationFps: 24
    property color renderedShineColor: shineColor
    property color colorFrom: shineColor
    property real colorStartedAt: 0.0
    property bool colorRunning: false
    property real audioAmplitude: 0.0
    property var amplitudeEnvelope: []
    property real amplitudeStartedAt: 0.0

    onShineColorChanged: {
        colorFrom = renderedShineColor
        colorStartedAt = Date.now()
        colorRunning = true
    }

    function mixColor(fromColor, toColor, amount) {
        return Qt.rgba(fromColor.r + (toColor.r - fromColor.r) * amount,
                       fromColor.g + (toColor.g - fromColor.g) * amount,
                       fromColor.b + (toColor.b - fromColor.b) * amount,
                       fromColor.a + (toColor.a - fromColor.a) * amount)
    }

    function setAmplitudeEnvelope(serializedEnvelope) {
        const parsed = serializedEnvelope.split("|")
        amplitudeEnvelope = parsed.map(function(value) {
            return Math.min(1.0, Math.max(0.0, Number(value)))
        })
        audioAmplitude = 0.0
        amplitudeStartedAt = Date.now()
    }

    function setAmplitude(value) {
        amplitudeEnvelope = []
        audioAmplitude = Math.min(1.0, Math.max(0.0, value))
    }

    function updateAnimation(now) {
        scanPhase = ((now - animationEpoch) % 30000) / 30000
        refreshPhase = -0.15 + 1.30 * (((now - animationEpoch) % 9000) / 9000)

        if (amplitudeEnvelope.length > 0) {
            const amplitudeIndex = Math.floor((now - amplitudeStartedAt)
                                              * animationFps / 1000)
            if (amplitudeIndex >= amplitudeEnvelope.length) {
                amplitudeEnvelope = []
                audioAmplitude = 0.0
            } else if (amplitudeIndex >= 0) {
                audioAmplitude = Math.min(1.0, Math.max(0.0,
                                                       amplitudeEnvelope[amplitudeIndex]))
            }
        }

        if (colorRunning) {
            const colorProgress = Math.min(1.0, Math.max(0.0,
                                                        (now - colorStartedAt) / 180.0))
            const colorEased = colorProgress < 0.5
                               ? 2.0 * colorProgress * colorProgress
                               : 1.0 - Math.pow(-2.0 * colorProgress + 2.0, 2.0) / 2.0
            renderedShineColor = mixColor(colorFrom, shineColor, colorEased)
            if (colorProgress >= 1.0) {
                renderedShineColor = shineColor
                colorRunning = false
            }
        }

        if (!powerRunning)
            return

        const progress = Math.min(1.0, Math.max(0.0,
                                               (now - powerStartedAt) / powerDuration))
        const eased = powerTo > powerFrom
                    ? 1.0 - Math.pow(1.0 - progress, 3.0)
                    : Math.pow(progress, 3.0)
        activationLevel = powerFrom + (powerTo - powerFrom) * eased

        if (progress >= 1.0) {
            activationLevel = powerTo
            powerRunning = false
        }
    }

    function animatePower(powered) {
        const now = Date.now()
        powerFrom = activationLevel
        powerTo = powered ? 1.0 : 0.0
        powerStartedAt = now
        powerDuration = powered ? 850.0 : 600.0
        powerRunning = true
        updateAnimation(now)
    }

    function turnOn() {
        if (active)
            animatePower(true)
        else
            active = true
    }

    function turnOff() {
        if (!active)
            animatePower(false)
        else
            active = false
    }

    onActiveChanged: animatePower(active)
    Component.onCompleted: animatePower(active)

    Timer {
        id: animationClock
        interval: Math.round(1000 / portrait.animationFps)
        repeat: true
        running: portrait.active || portrait.powerRunning || portrait.colorRunning
                 || portrait.activationLevel > 0.001
        onTriggered: portrait.updateAnimation(Date.now())
    }

    // True layer-shell overlay without reserving workspace or accepting focus/input.
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell:hk47-avatar"
    focusable: false
    exclusionMode: ExclusionMode.Ignore
    exclusiveZone: 0
    mask: Region {}

    anchors {
        left: true
        bottom: true
    }

    margins {
        left: Math.round((portrait.screen ? portrait.screen.width : 2560) / 2
                         - portrait.implicitWidth / 2)
        bottom: Math.round((portrait.screen ? portrait.screen.height : 1440) / 4
                           - portrait.implicitHeight / 2)
    }

    // Exact-size source texture; the shader performs the visible colorization.
    Image {
        id: portraitImage
        anchors.fill: parent
        source: "file:///games/Windows/VM-Share/ClipStudio_Project/HK-47.png"
        sourceSize.width: 256
        sourceSize.height: 256
        fillMode: Image.PreserveAspectFit
        smooth: false
        mipmap: false
        cache: true
        asynchronous: true
        opacity: 0.01 * portrait.activationLevel
    }

    // Move only a repeated scanline texture; the portrait and window stay fixed.
    Item {
        anchors.fill: parent
        clip: true

        Image {
            id: crtImage
            width: parent.width
            height: parent.height * 2
            y: -portrait.implicitHeight + portrait.scanPhase * portrait.implicitHeight
            source: "file:///games/Windows/VM-Share/ClipStudio_Project/HK-47_CRT_effect.png"
            sourceSize.width: 256
            sourceSize.height: 256
            fillMode: Image.TileVertically
            smooth: false
            mipmap: false
            cache: true
            asynchronous: true
            opacity: 0.01 * portrait.activationLevel

        }

        // One small GPU pass creates the translucent blue hologram, localized
        // shine, moving scanlines, refresh sweep, halo, and restrained flicker.
        ShaderEffect {
            anchors.fill: parent
            blending: true
            fragmentShader: Qt.resolvedUrl("shaders/avatar-shine.frag.qsb")

            property var portraitTexture: portraitImage
            property var crtTexture: crtImage
            property real scanPhase: portrait.scanPhase
            property real refreshPhase: portrait.refreshPhase
            property real activationLevel: portrait.activationLevel
            property color shineColor: portrait.renderedShineColor
            property real shineStrength: portrait.effectiveShineStrength
            property real hologramOpacity: portrait.hologramOpacity
            property real glowStrength: portrait.glowStrength
            property real audioAmplitude: portrait.visualAmplitude
            property real silhouetteOpacity: portrait.silhouetteOpacity
            property real silhouetteScale: portrait.silhouetteScale
            property real silhouetteOffsetY: portrait.silhouetteOffsetY
            property real silhouetteFeatherPixels: portrait.silhouetteFeatherPixels
        }
    }
}
