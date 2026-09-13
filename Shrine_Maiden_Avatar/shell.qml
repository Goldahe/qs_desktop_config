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
        function profileId(): string { return "shrine-maiden" }
    }
}
