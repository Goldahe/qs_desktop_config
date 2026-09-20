import Quickshell
import Quickshell.Io

ShellRoot {
    id: root
    property bool profileAllowed: false
    readonly property string controller: Quickshell.env("HOME") + "/.config/quickshell/main/avatar-control.py"

    Process {
        command: ["python", root.controller, "allowed", "shrine-maiden"]
        running: true
        onExited: function(exitCode) {
            if (exitCode !== 0) {
                Qt.quit()
                return
            }
            root.profileAllowed = true
        }
    }

    Portrait {
        id: portrait
        visible: root.profileAllowed
    }

    IpcHandler {
        target: "shrineMaidenAvatar"
        function isActive(): bool { return portrait.active }
        function activate(): void { portrait.showAvatar() }
        function deactivate(): void { portrait.hideAvatar() }
        function setAmplitudeEnvelope(envelope: string): void {
            portrait.setAmplitudeEnvelope(envelope)
        }
        function setAmplitude(amplitude: real): void {
            portrait.setAmplitude(amplitude)
        }
        function mouthFrame(): int { return portrait.mouthFrame }
        function mouthAsset(): string { return portrait.mouthAsset }
        function profileId(): string { return "shrine-maiden" }
    }
}
