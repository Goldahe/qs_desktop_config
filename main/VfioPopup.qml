import QtQuick
import Quickshell
import Quickshell.Io

PopupWindow {
    id: vfioPopup

    property var barWindow
    property string modeText: "Checking…"
    property string driverText: "unknown"
    property string vmText: "Checking…"
    property string nvidiaText: "Checking…"
    property string holdersText: "Checking…"
    property string actionName: "Ready"
    property string actionStdout: ""
    property string actionStderr: ""
    property string actionMessage: "Select an operation to see its result here."
    property bool actionSucceeded: true
    readonly property bool stateKnown: driverText !== "unknown"
    readonly property bool vfioMode: driverText === "vfio-pci"
    readonly property bool actionRunning: actionProcess.running
    readonly property bool startEnabled: stateKnown && !vfioMode && !actionRunning
    readonly property bool stopEnabled: stateKnown && vfioMode && !actionRunning

    anchor.window: barWindow
    anchor.rect.x: (barWindow.width - width) / 2
    anchor.rect.y: barWindow.height - barWindow.taskbarHeight - 3
    anchor.gravity: Edges.Top | Edges.Right
    implicitWidth: 430
    implicitHeight: 520
    color: "transparent"
    visible: false
    grabFocus: false

    function valueFor(output, key, fallback) {
        const lines = output.split("\n")
        for (const line of lines) {
            const prefix = key + "|"
            if (line.indexOf(prefix) === 0)
                return line.slice(prefix.length)
        }
        return fallback
    }

    function updateStatus(output) {
        modeText = valueFor(output, "MODE", "Unknown")
        driverText = valueFor(output, "DRIVER", "unknown")
        vmText = valueFor(output, "VM", "unavailable")
        nvidiaText = valueFor(output, "NVIDIA", "Unavailable")
        holdersText = valueFor(output, "HOLDERS", "Unknown")
    }

    function refresh() {
        if (!statusProcess.running)
            statusProcess.running = true
    }

    function togglePopup() {
        visible = !visible
        if (visible)
            refresh()
    }

    function runAction(name, command) {
        if (actionProcess.running)
            return
        actionName = name
        actionStdout = ""
        actionStderr = ""
        actionMessage = name + " in progress…"
        actionSucceeded = true
        actionProcess.command = command
        actionProcess.running = true
    }

    function finishAction(exitCode) {
        const combined = (actionStdout + (actionStdout.length > 0 && actionStderr.length > 0 ? "\n" : "") + actionStderr).trim()
        actionSucceeded = exitCode === 0
        actionMessage = combined.length > 0 ? combined : (actionSucceeded ? actionName + " completed." : actionName + " failed with exit code " + exitCode + ".")
        refresh()
    }

    function runDiagnostics() {
        runAction("Full diagnostics", ["sudo", "-n", "/usr/local/sbin/rtx2080-switch", "status"])
    }

    onVisibleChanged: if (visible) refresh()

    Process {
        id: statusProcess
        running: false
        command: ["/home/hawk/.config/quickshell/main/vfio-status.sh"]
        stdout: StdioCollector {
            onStreamFinished: vfioPopup.updateStatus(this.text)
        }
    }

    Process {
        id: actionProcess
        running: false
        stdout: StdioCollector {
            onStreamFinished: vfioPopup.actionStdout = this.text
        }
        stderr: StdioCollector {
            onStreamFinished: vfioPopup.actionStderr = this.text
        }
        onExited: (exitCode, exitStatus) => {
            actionFinishTimer.exitCode = exitCode
            actionFinishTimer.restart()
        }
    }

    Timer {
        id: actionFinishTimer
        property int exitCode: 0
        interval: 100
        repeat: false
        onTriggered: vfioPopup.finishAction(exitCode)
    }

    Timer {
        interval: 2000
        running: vfioPopup.visible
        repeat: true
        onTriggered: vfioPopup.refresh()
    }

    Rectangle {
        anchors.fill: parent
        radius: 10
        color: "#f21d2026"
        border.color: "#59616d"
        border.width: 1

        Column {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 9

            Text {
                text: "󰢮  RTX 2080 Assignment"
                color: "#e8edf5"
                font.family: "Symbols Nerd Font"
                font.pixelSize: 17
                font.bold: true
            }

            Rectangle { width: parent.width; height: 1; color: "#4b5360" }

            Text {
                text: "Start/Stop"
                color: "#8fb8ff"
                font.pixelSize: 13
                font.bold: true
            }

            Row {
                width: parent.width
                spacing: 10

                Rectangle {
                    width: (parent.width - 10) / 2
                    height: 44
                    radius: 6
                    opacity: vfioPopup.startEnabled ? 1.0 : 0.38
                    color: vfioPopup.startEnabled && startMouse.containsMouse ? "#315b42" : "#263a31"
                    border.color: vfioPopup.startEnabled ? "#69c486" : "#59616d"

                    Text {
                        anchors.centerIn: parent
                        text: "▶  Start VM"
                        color: vfioPopup.startEnabled ? "#b8f5c8" : "#8a9099"
                        font.pixelSize: 14
                        font.bold: true
                    }

                    MouseArea {
                        id: startMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: vfioPopup.startEnabled
                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: vfioPopup.runAction("Starting win11-VFIO", ["/home/hawk/.local/bin/win11-vfio", "start"])
                    }
                }

                Rectangle {
                    width: (parent.width - 10) / 2
                    height: 44
                    radius: 6
                    opacity: vfioPopup.stopEnabled ? 1.0 : 0.38
                    color: vfioPopup.stopEnabled && stopMouse.containsMouse ? "#66383b" : "#402b2e"
                    border.color: vfioPopup.stopEnabled ? "#df777d" : "#59616d"

                    Text {
                        anchors.centerIn: parent
                        text: "■  Stop VM"
                        color: vfioPopup.stopEnabled ? "#ffc0c4" : "#8a9099"
                        font.pixelSize: 14
                        font.bold: true
                    }

                    MouseArea {
                        id: stopMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: vfioPopup.stopEnabled
                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: vfioPopup.runAction("Stopping win11-VFIO", ["/home/hawk/.local/bin/win11-vfio", "stop"])
                    }
                }
            }

            Text {
                text: "Diagnostics"
                color: "#8fb8ff"
                font.pixelSize: 13
                font.bold: true
                topPadding: 4
            }

            Rectangle {
                width: parent.width
                height: 130
                radius: 6
                color: "#aa15181d"
                border.color: "#3f4650"

                Column {
                    anchors.fill: parent
                    anchors.margins: 11
                    spacing: 6

                    Text { text: "Mode:  " + vfioPopup.modeText; color: vfioPopup.vfioMode ? "#d7bdff" : "#9be9a8"; font.pixelSize: 13; font.bold: true }
                    Text { text: "Driver:  " + vfioPopup.driverText; color: "#d8dde6"; font.pixelSize: 12 }
                    Text { text: "VM:  " + vfioPopup.vmText; color: "#d8dde6"; font.pixelSize: 12 }
                    Text { text: "NVIDIA:  " + vfioPopup.nvidiaText; color: "#d8dde6"; font.pixelSize: 12; elide: Text.ElideRight; width: parent.width }
                    Text { text: "Visible holders:  " + vfioPopup.holdersText; color: "#d8dde6"; font.pixelSize: 12 }
                }
            }

            Row {
                width: parent.width
                spacing: 10

                Rectangle {
                    width: (parent.width - 10) / 2
                    height: 38
                    radius: 5
                    color: refreshMouse.containsMouse ? "#39424e" : "#2b323b"
                    border.color: "#59616d"
                    Text { anchors.centerIn: parent; text: "↻  Refresh"; color: "#e0e5ec"; font.pixelSize: 13 }
                    MouseArea {
                        id: refreshMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: !statusProcess.running
                        cursorShape: Qt.PointingHandCursor
                        onClicked: vfioPopup.refresh()
                    }
                }

                Rectangle {
                    width: (parent.width - 10) / 2
                    height: 38
                    radius: 5
                    color: diagnosticsMouse.containsMouse ? "#39424e" : "#2b323b"
                    border.color: "#59616d"
                    Text { anchors.centerIn: parent; text: "󰒓  Full diagnostics"; color: "#e0e5ec"; font.family: "Symbols Nerd Font"; font.pixelSize: 13 }
                    MouseArea {
                        id: diagnosticsMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: !vfioPopup.actionRunning
                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: vfioPopup.runDiagnostics()
                    }
                }
            }

            Text {
                text: vfioPopup.actionRunning ? "Operation output · running" : "Operation output"
                color: vfioPopup.actionRunning ? "#ffd37d" : (vfioPopup.actionSucceeded ? "#8fb8ff" : "#ff9098")
                font.pixelSize: 13
                font.bold: true
            }

            Rectangle {
                width: parent.width
                height: 104
                radius: 6
                color: "#cc101318"
                border.color: vfioPopup.actionRunning ? "#92713b" : (vfioPopup.actionSucceeded ? "#3f4650" : "#8f454b")
                clip: true

                Flickable {
                    anchors.fill: parent
                    anchors.margins: 10
                    contentWidth: width
                    contentHeight: outputText.contentHeight
                    boundsBehavior: Flickable.StopAtBounds
                    clip: true

                    Text {
                        id: outputText
                        width: parent.width
                        text: vfioPopup.actionMessage
                        color: vfioPopup.actionRunning ? "#ffdca0" : (vfioPopup.actionSucceeded ? "#cfd6df" : "#ffb0b5")
                        font.family: "monospace"
                        font.pixelSize: 11
                        wrapMode: Text.Wrap
                    }
                }
            }

            Text {
                width: parent.width
                text: vfioPopup.actionRunning ? vfioPopup.actionName : (vfioPopup.vfioMode ? "RTX is assigned away from Arch." : "RTX is available to Arch compute workloads.")
                color: "#8d949e"
                font.pixelSize: 11
                horizontalAlignment: Text.AlignHCenter
            }
        }
    }
}
