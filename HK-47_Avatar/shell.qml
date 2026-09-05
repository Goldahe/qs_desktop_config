import Quickshell
import Quickshell.Io

ShellRoot {
    id: root
    property bool gameMode: false
    property bool modeKnown: false

    Process {
        id: modeStateProcess
        command: ["sh", "-c", "grep -qx game \"$XDG_RUNTIME_DIR/quickshell-display-mode\""]
        running: true
        onExited: function(exitCode) {
            if (exitCode === 0) {
                Qt.quit()
                return
            }
            root.gameMode = false
            root.modeKnown = true
        }
    }

    AvatarPortrait {
        id: avatar
        visible: root.modeKnown && !root.gameMode
    }

    HologramBeam {
        avatar: avatar
        visible: root.modeKnown && !root.gameMode
    }

    IpcHandler {
        target: "hk47Avatar"

        function isActive(): bool {
            return avatar.active
        }

        function turnOn(): void {
            avatar.turnOn()
        }

        function turnOff(): void {
            avatar.turnOff()
        }

        function toggle(): void {
            if (avatar.active)
                avatar.turnOff()
            else
                avatar.turnOn()
        }

        function setColor(color: string): void {
            avatar.shineColor = color
        }

        function setAmplitudeEnvelope(envelope: string): void {
            avatar.setAmplitudeEnvelope(envelope)
        }

        function setAmplitude(amplitude: real): void {
            avatar.setAmplitude(amplitude)
        }

        function getAmplitude(): real {
            return avatar.audioAmplitude
        }

        function getShineStrength(): real {
            return avatar.effectiveShineStrength
        }
    }
}
