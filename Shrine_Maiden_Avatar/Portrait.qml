import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: portrait

    implicitWidth: 256
    implicitHeight: 384
    color: "transparent"
    property bool active: false
    property real audioAmplitude: 0.0
    property var amplitudeEnvelope: []
    property real amplitudeStartedAt: 0.0
    // Four source portraits provide progressively wider speech shapes.
    // The frame transitions use separate opening/closing thresholds so a
    // sustained vowel does not make the portrait chatter at a boundary.
    property int mouthFrame: 0
    readonly property int mouthIdleFrame: 0
    readonly property int mouthOpenFrame: 1
    readonly property int mouthOFrame: 2
    readonly property int mouthMoreFrame: 3
    readonly property real mouthOpenThreshold: 0.10
    readonly property real mouthOThreshold: 0.30
    readonly property real mouthMoreThreshold: 0.58
    readonly property real mouthOpenCloseThreshold: 0.07
    readonly property real mouthOCloseThreshold: 0.24
    readonly property real mouthMoreCloseThreshold: 0.48
    readonly property string mouthAsset: mouthFrame === mouthIdleFrame
        ? "FireKeeper_idle.png"
        : mouthFrame === mouthOpenFrame
            ? "FireKeeper_open.png"
            : mouthFrame === mouthOFrame
                ? "FireKeeper_open_O.png"
                : "FireKeeper_open_more.png"
    readonly property int animationFps: 24
    readonly property int taskbarHeight: 38
    readonly property string avatarAssetRoot: "file://" + Quickshell.env("HOME") + "/Avatar/"

    // Presence is separate from active so dismissal can finish visibly.
    property real presenceLevel: 0.0
    property real presenceFrom: 0.0
    property real presenceTo: 0.0
    property real presenceStartedAt: 0.0
    property real presenceDuration: 720.0
    property bool presenceRunning: false
    property real summonPhase: 0.0
    property real emberLevel: 0.0

    function showAvatar() {
        active = true
        animatePresence(true)
    }

    function hideAvatar() {
        active = false
        animatePresence(false)
    }

    function animatePresence(showing) {
        presenceFrom = presenceLevel
        presenceTo = showing ? 1.0 : 0.0
        presenceStartedAt = Date.now()
        presenceDuration = showing ? 820.0 : 560.0
        presenceRunning = true
        updatePresence(Date.now())
    }

    function updatePresence(now) {
        if (!presenceRunning)
            return
        const progress = Math.min(1.0, Math.max(0.0,
            (now - presenceStartedAt) / presenceDuration))
        // A soft rise on arrival and a slower settling fade on departure.
        const eased = presenceTo > presenceFrom
            ? 1.0 - Math.pow(1.0 - progress, 3.0)
            : Math.pow(progress, 2.0)
        presenceLevel = presenceFrom + (presenceTo - presenceFrom) * eased
        summonPhase = progress
        emberLevel = presenceRunning ? Math.sin(progress * Math.PI) : 0.0
        if (progress >= 1.0) {
            presenceLevel = presenceTo
            emberLevel = 0.0
            presenceRunning = false
        }
    }

    function setAmplitudeEnvelope(serializedEnvelope) {
        const parsed = String(serializedEnvelope || "").split("|")
        amplitudeEnvelope = parsed.filter(function(value) { return value !== "" }).map(function(value) {
            const numeric = Number(value)
            return Number.isFinite(numeric)
                ? Math.min(1.0, Math.max(0.0, numeric))
                : 0.0
        })
        audioAmplitude = 0.0
        amplitudeStartedAt = Date.now()
        updateMouthState()
    }

    function setAmplitude(value) {
        amplitudeEnvelope = []
        const numeric = Number(value)
        audioAmplitude = Number.isFinite(numeric)
            ? Math.min(1.0, Math.max(0.0, numeric))
            : 0.0
        updateMouthState()
    }

    function mouthBand(value) {
        if (value < mouthOpenThreshold)
            return mouthIdleFrame
        if (value < mouthOThreshold)
            return mouthOpenFrame
        if (value < mouthMoreThreshold)
            return mouthOFrame
        return mouthMoreFrame
    }

    function updateMouthState() {
        const requested = mouthBand(audioAmplitude)
        if (requested > mouthFrame) {
            // Opening uses the normal band thresholds.
            mouthFrame = requested
            return
        }
        if (requested < mouthFrame) {
            // Closing waits for a slightly lower level to avoid edge chatter.
            const closeThresholds = [
                mouthOpenCloseThreshold,
                mouthOCloseThreshold,
                mouthMoreCloseThreshold,
            ]
            if (audioAmplitude < closeThresholds[mouthFrame - 1])
                mouthFrame = requested
        }
    }

    function updateAmplitude(now) {
        updatePresence(now)
        if (amplitudeEnvelope.length > 0) {
            const index = Math.floor((now - amplitudeStartedAt) * animationFps / 1000)
            if (index >= amplitudeEnvelope.length) {
                amplitudeEnvelope = []
                audioAmplitude = 0.0
            } else if (index >= 0) {
                audioAmplitude = amplitudeEnvelope[index]
            }
        }
        updateMouthState()
    }

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell:shrine-maiden-avatar"
    focusable: false
    exclusionMode: ExclusionMode.Ignore
    exclusiveZone: 0
    mask: Region {}

    anchors {
        left: true
        bottom: true
    }
    margins {
        left: Math.round((portrait.screen ? portrait.screen.width : 2560) * 0.8
                         - portrait.implicitWidth / 2)
        // Let the avatar's lower edge meet the physical screen edge.
        bottom: 0
    }

    // The portrait rises from the floor of the shrine as its presence gathers.
    Item {
        id: summonedPresence
        anchors.fill: parent
        y: Math.round((1.0 - portrait.presenceLevel) * 42)
        scale: 0.88 + portrait.presenceLevel * 0.12
        opacity: portrait.presenceLevel

        // A visible ember veil accompanies the arrival and departure.
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            y: parent.height * 0.44
            width: 178 + portrait.presenceLevel * 46
            height: 132 + portrait.presenceLevel * 30
            radius: height / 2
            color: "#66e0a45d"
            opacity: portrait.emberLevel * 0.72
            scale: 0.72 + portrait.emberLevel * 0.34
        }

        // Rising motes give the transition a clear, Souls-like silhouette.
        Repeater {
            model: 6
            delegate: Rectangle {
                required property int index
                width: 4 + (index % 2) * 2
                height: width
                radius: width / 2
                x: 38 + index * 34
                y: parent.height * (0.82 - (index % 3) * 0.08)
                   - portrait.summonPhase * (28 + index * 6)
                color: index % 2 === 0 ? "#ffd79a" : "#e98b54"
                opacity: portrait.emberLevel * (0.72 - index * 0.07)
                visible: opacity > 0.01
            }
        }

        Image {
            anchors.fill: parent
            source: portrait.avatarAssetRoot + portrait.mouthAsset
            sourceSize.width: 256
            sourceSize.height: 384
            fillMode: Image.PreserveAspectFit
            smooth: false
            mipmap: false
            cache: true
            asynchronous: true
        }
    }

    Timer {
        interval: Math.round(1000 / portrait.animationFps)
        repeat: true
        running: portrait.active || portrait.presenceRunning
                   || portrait.amplitudeEnvelope.length > 0
        onTriggered: portrait.updateAmplitude(Date.now())
    }
}
