import QtQuick
import Quickshell
import Quickshell.Io

Rectangle {
    id: chatterboxButton

    property var barWindow
    property bool serverRunning: false
    readonly property string runtimeDirectory: String(Quickshell.env("XDG_RUNTIME_DIR"))
    readonly property string statusFile: runtimeDirectory + "/chatterbox.status"

    visible: serverRunning

    width: 30
    height: 28
    radius: 5
    color: chatterboxMouse.containsMouse
        ? (serverRunning ? "#304f38" : "#454545")
        : "transparent"

    Process {
        id: statusProcess
        command: ["sh", "-c", "ss -ltn | grep -Eq ':(8004|8005) '"]
        running: false
        onExited: function(exitCode, exitStatus) {
            chatterboxButton.serverRunning = exitCode === 0
        }
    }

    FileView {
        id: lifecycleFile
        path: chatterboxButton.statusFile
        watchChanges: true
        printErrors: false
        onFileChanged: {
            reload()
            chatterboxButton.updateLifecycleState()
        }
        onLoaded: chatterboxButton.updateLifecycleState()
    }

    function updateLifecycleState() {
        const state = lifecycleFile.text().trim()
        if (state === "running") {
            serverRunning = true
            return
        }
        if (state === "starting" || state === "failed" || state === "stopped") {
            serverRunning = false
            return
        }
        if (!statusProcess.running)
            statusProcess.running = true
    }

    Timer {
        // Reconcile crashes or missed file events without constant polling.
        interval: 60000
        running: true
        repeat: true
        onTriggered: if (!statusProcess.running) statusProcess.running = true
    }

    Component.onCompleted: updateLifecycleState()

    Text {
        anchors.centerIn: parent
        text: "󰍬"
        color: serverRunning ? "#9be9a8" : "#858585"
        font.family: "Symbols Nerd Font"
        font.pixelSize: 17
    }

    MouseArea {
        id: chatterboxMouse
        anchors.fill: parent
        hoverEnabled: true
        onClicked: barWindow.chatterboxMenu.visible = !barWindow.chatterboxMenu.visible
        cursorShape: Qt.PointingHandCursor
    }
}
