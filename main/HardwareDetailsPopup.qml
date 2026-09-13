import QtQuick
import Quickshell
import Quickshell.Io
import "ShellTheme.js" as ShellTheme

LifecycleFloating {
    id: detailsPopup

    property var barWindow
    property var hardwareSource
    property int selectedTab: 0
    property var selectedProcess: null
    property bool terminationConfirmationVisible: false
    property bool terminationInProgress: false
    property string terminationStatus: ""
    readonly property var tabs: ["CPU", "GPU", "RAM", "SSD/Memory"]

    function requestTermination(process) {
        if (!process || !/^[1-9][0-9]*$/.test(String(process.pid)))
            return
        selectedProcess = process
        terminationStatus = ""
        terminationConfirmationVisible = true
    }

    function cancelTermination() {
        if (terminationInProgress)
            return
        terminationConfirmationVisible = false
        selectedProcess = null
        terminationStatus = ""
    }

    function confirmTermination() {
        if (!selectedProcess || terminationInProgress)
            return
        terminationStatus = ""
        terminationInProgress = true
        terminateProcess.running = true
    }

    function gpuName(index) {
        if (hardwareSource && hardwareSource.gpuHistory[index])
            return hardwareSource.gpuHistory[index].name
        return "GPU " + (index + 1)
    }

    title: "HK-47 Hardware Details"
    // The detail surface tracks the taskbar's monitor at 75% of each dimension.
    implicitWidth: Math.round((barWindow && barWindow.screen ? barWindow.screen.width : 2560) * 0.75)
    implicitHeight: Math.round((barWindow && barWindow.screen ? barWindow.screen.height : 1440) * 0.75)
    color: "transparent"
    visible: false

    Process {
        id: terminateProcess
        property string output: ""
        command: [Qt.resolvedUrl("terminate-process.sh").toString().replace("file://", ""),
                  detailsPopup.selectedProcess ? String(detailsPopup.selectedProcess.pid) : "",
                  detailsPopup.selectedProcess ? String(detailsPopup.selectedProcess.name) : ""]
        running: false
        stdout: StdioCollector { onStreamFinished: terminateProcess.output = this.text.trim() }
        stderr: StdioCollector { onStreamFinished: terminateProcess.output = this.text.trim() }
        onExited: function(exitCode) {
            detailsPopup.terminationInProgress = false
            detailsPopup.terminationStatus = terminateProcess.output.length > 0
                ? terminateProcess.output
                : (exitCode === 0 ? "SIGTERM sent." : "Unable to terminate the selected process.")
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: 10
        color: ShellTheme.color("#f21d2026")
        border.color: ShellTheme.color("#59616d")
        border.width: 1

        Column {
            anchors.fill: parent
            anchors.margins: 18
            spacing: 12

            Text {
                text: "󰍛  Hardware Details"
                color: ShellTheme.color("#e8edf5")
                font.family: "Symbols Nerd Font"
                font.pixelSize: 18
                font.bold: true
            }

            Row {
                width: parent.width
                height: 38
                spacing: 6

                Repeater {
                    model: detailsPopup.tabs
                    delegate: Rectangle {
                        required property int index
                        property string tabName: detailsPopup.tabs[index]
                        width: (parent.width - 18) / 4
                        height: 38
                        radius: 6
                        color: detailsPopup.selectedTab === index ? ShellTheme.color("#536d9b") : (tabMouse.containsMouse ? ShellTheme.color("#39424e") : ShellTheme.color("#2b323b"))
                        border.color: detailsPopup.selectedTab === index ? ShellTheme.color("#8fb8ff") : ShellTheme.color("#59616d")

                        Text {
                            anchors.centerIn: parent
                            text: tabName
                            color: ShellTheme.color("#e8edf5")
                            font.pixelSize: 13
                            font.bold: detailsPopup.selectedTab === index
                        }

                        MouseArea {
                            id: tabMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: detailsPopup.selectedTab = index
                        }
                    }
                }
            }

            Rectangle { width: parent.width; height: 1; color: ShellTheme.color("#4b5360") }
            Text { text: "Click a process row to offer graceful termination."; color: ShellTheme.color("#aebdca"); font.pixelSize: 12 }

            Flickable {
                width: parent.width
                height: parent.height - 138
                contentWidth: width
                contentHeight: cpuColumn.implicitHeight
                clip: true
                visible: detailsPopup.selectedTab === 0

                Column {
                    id: cpuColumn
                    width: parent.width
                    spacing: 9

                    Text { text: hardwareSource.cpuName; color: ShellTheme.color("#e8edf5"); font.pixelSize: 15; font.bold: true; wrapMode: Text.Wrap; width: parent.width }
                    Text { text: "Load: " + hardwareSource.cpuLoad + "    Cores: " + hardwareSource.cpuCores + "    Temperature: " + hardwareSource.cpuTemperature; color: ShellTheme.color("#aebdca"); font.pixelSize: 12 }

                    Rectangle {
                        width: parent.width
                        height: 28
                        color: ShellTheme.color("#263843")
                        Row {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            Text { width: 190; text: "Process"; color: ShellTheme.color("#bfeaff"); font.pixelSize: 11; font.bold: true; verticalAlignment: Text.AlignVCenter }
                            Text { width: 55; text: "CPU"; color: ShellTheme.color("#bfeaff"); font.pixelSize: 11; font.bold: true; verticalAlignment: Text.AlignVCenter }
                            Text { width: 55; text: "MEM"; color: ShellTheme.color("#bfeaff"); font.pixelSize: 11; font.bold: true; verticalAlignment: Text.AlignVCenter }
                            Text { width: 70; text: "PID"; color: ShellTheme.color("#bfeaff"); font.pixelSize: 11; font.bold: true; verticalAlignment: Text.AlignVCenter }
                            Text { width: 85; text: "RSS / VSZ"; color: ShellTheme.color("#bfeaff"); font.pixelSize: 11; font.bold: true; verticalAlignment: Text.AlignVCenter }
                            Text { width: 110; text: "User / Time"; color: ShellTheme.color("#bfeaff"); font.pixelSize: 11; font.bold: true; verticalAlignment: Text.AlignVCenter }
                            Text { width: 100; text: "State / TTY\nNice / NI"; color: ShellTheme.color("#bfeaff"); font.pixelSize: 11; font.bold: true; verticalAlignment: Text.AlignVCenter }
                            Text { width: parent.width - 665; text: "Command"; color: ShellTheme.color("#bfeaff"); font.pixelSize: 11; font.bold: true; verticalAlignment: Text.AlignVCenter }
                        }
                    }

                    Repeater {
                        model: hardwareSource.processes
                        delegate: Rectangle {
                            required property var modelData
                            width: cpuColumn.width
                            height: 42
                            color: ShellTheme.color("#f21d2026")
                            MouseArea {
                                anchors.fill: parent
                                z: 1
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: detailsPopup.requestTermination(modelData)
                            }
                            Row {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                Text { width: 190; text: modelData.name; color: ShellTheme.color("#e8edf5"); font.pixelSize: 11; elide: Text.ElideRight; verticalAlignment: Text.AlignVCenter }
                                Text { width: 55; text: modelData.cpu + "%"; color: ShellTheme.color("#d8d8d8"); font.pixelSize: 11; verticalAlignment: Text.AlignVCenter }
                                Text { width: 55; text: modelData.memory + "%"; color: ShellTheme.color("#d8d8d8"); font.pixelSize: 11; verticalAlignment: Text.AlignVCenter }
                                Text { width: 70; text: modelData.pid; color: ShellTheme.color("#d8d8d8"); font.pixelSize: 11; verticalAlignment: Text.AlignVCenter }
                                Text { width: 85; text: hardwareSource.formatKiB(modelData.rss) + " / " + hardwareSource.formatKiB(modelData.vsz); color: ShellTheme.color("#d8d8d8"); font.pixelSize: 10; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight }
                                Text { width: 110; text: modelData.user + " / " + modelData.elapsed; color: ShellTheme.color("#d8d8d8"); font.pixelSize: 10; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight }
                                Text { width: 100; text: modelData.stat + " / " + modelData.tty + "\nN: " + modelData.nice + " / " + modelData.ni; color: ShellTheme.color("#d8d8d8"); font.pixelSize: 10; verticalAlignment: Text.AlignVCenter }
                                Text { width: parent.width - 665; text: modelData.command; color: ShellTheme.color("#b9c7d1"); font.pixelSize: 10; elide: Text.ElideRight; verticalAlignment: Text.AlignVCenter }
                            }
                        }
                    }
                }
            }

            Flickable {
                width: parent.width
                height: parent.height - 138
                contentWidth: width
                contentHeight: gpuColumn.implicitHeight
                clip: true
                visible: detailsPopup.selectedTab === 1

                Column {
                    id: gpuColumn
                    width: parent.width
                    spacing: 12

                    Repeater {
                        model: hardwareSource.gpuCount
                        delegate: Column {
                            required property int index
                            width: gpuColumn.width
                            spacing: 7

                            Text { text: gpuName(index); color: ShellTheme.color("#8fb8ff"); font.pixelSize: 15; font.bold: true }
                            Rectangle {
                                width: parent.width
                                height: 28
                                color: ShellTheme.color("#263843")
                                Row {
                                    anchors.fill: parent
                                    anchors.leftMargin: 8
                                    anchors.rightMargin: 8
                                    Text { width: 120; text: "Process"; color: ShellTheme.color("#bfeaff"); font.pixelSize: 11; font.bold: true; verticalAlignment: Text.AlignVCenter }
                                    Text { width: 55; text: "GPU"; color: ShellTheme.color("#bfeaff"); font.pixelSize: 11; font.bold: true; verticalAlignment: Text.AlignVCenter }
                                    Text { width: 80; text: "VRAM"; color: ShellTheme.color("#bfeaff"); font.pixelSize: 11; font.bold: true; verticalAlignment: Text.AlignVCenter }
                                    Text { width: 50; text: "CPU"; color: ShellTheme.color("#bfeaff"); font.pixelSize: 11; font.bold: true; verticalAlignment: Text.AlignVCenter }
                                    Text { width: 50; text: "MEM"; color: ShellTheme.color("#bfeaff"); font.pixelSize: 11; font.bold: true; verticalAlignment: Text.AlignVCenter }
                                    Text { width: 60; text: "PID"; color: ShellTheme.color("#bfeaff"); font.pixelSize: 11; font.bold: true; verticalAlignment: Text.AlignVCenter }
                                    Text { width: 90; text: "User / Time"; color: ShellTheme.color("#bfeaff"); font.pixelSize: 11; font.bold: true; verticalAlignment: Text.AlignVCenter }
                                    Text { width: 95; text: "RSS / VSZ"; color: ShellTheme.color("#bfeaff"); font.pixelSize: 11; font.bold: true; verticalAlignment: Text.AlignVCenter }
                                    Text { width: 55; text: "State"; color: ShellTheme.color("#bfeaff"); font.pixelSize: 11; font.bold: true; verticalAlignment: Text.AlignVCenter }
                                    Text { width: parent.width - 655; text: "Command"; color: ShellTheme.color("#bfeaff"); font.pixelSize: 11; font.bold: true; verticalAlignment: Text.AlignVCenter }
                                }
                            }

                            Repeater {
                                model: hardwareSource.gpuProcesses[index]
                                delegate: Rectangle {
                                    required property var modelData
                                    width: gpuColumn.width
                                    height: 42
                                    color: ShellTheme.color("#f21d2026")
                                    MouseArea {
                                        anchors.fill: parent
                                        z: 1
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: detailsPopup.requestTermination(modelData)
                                    }
                                    Row {
                                        anchors.fill: parent
                                        anchors.leftMargin: 8
                                        anchors.rightMargin: 8
                                        Text { width: 120; text: modelData.name; color: ShellTheme.color("#e8edf5"); font.pixelSize: 11; elide: Text.ElideRight; verticalAlignment: Text.AlignVCenter }
                                        Text { width: 55; text: modelData.gpuLoad === "N/A" ? "N/A" : modelData.gpuLoad + "%"; color: ShellTheme.color("#d8d8d8"); font.pixelSize: 11; verticalAlignment: Text.AlignVCenter }
                                        Text { width: 80; text: modelData.gpuMemory; color: ShellTheme.color("#d8d8d8"); font.pixelSize: 10; elide: Text.ElideRight; verticalAlignment: Text.AlignVCenter }
                                        Text { width: 50; text: modelData.cpu + "%"; color: ShellTheme.color("#d8d8d8"); font.pixelSize: 11; verticalAlignment: Text.AlignVCenter }
                                        Text { width: 50; text: modelData.memory + "%"; color: ShellTheme.color("#d8d8d8"); font.pixelSize: 11; verticalAlignment: Text.AlignVCenter }
                                        Text { width: 60; text: modelData.pid; color: ShellTheme.color("#d8d8d8"); font.pixelSize: 11; verticalAlignment: Text.AlignVCenter }
                                        Text { width: 90; text: modelData.user + " / " + modelData.elapsed; color: ShellTheme.color("#d8d8d8"); font.pixelSize: 10; elide: Text.ElideRight; verticalAlignment: Text.AlignVCenter }
                                        Text { width: 95; text: hardwareSource.formatKiB(modelData.rss) + " / " + hardwareSource.formatKiB(modelData.vsz); color: ShellTheme.color("#d8d8d8"); font.pixelSize: 10; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight }
                                        Text { width: 55; text: modelData.stat; color: ShellTheme.color("#d8d8d8"); font.pixelSize: 10; verticalAlignment: Text.AlignVCenter }
                                        Text { width: parent.width - 655; text: modelData.command; color: ShellTheme.color("#b9c7d1"); font.pixelSize: 10; elide: Text.ElideRight; verticalAlignment: Text.AlignVCenter }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Flickable {
                width: parent.width
                height: parent.height - 138
                contentWidth: width
                contentHeight: ramColumn.implicitHeight
                clip: true
                visible: detailsPopup.selectedTab === 2

                Column {
                    id: ramColumn
                    width: parent.width
                    spacing: 9

                    Text { text: "RAM processes"; color: ShellTheme.color("#8fb8ff"); font.pixelSize: 15; font.bold: true }
                    Text { text: "Total: " + hardwareSource.memoryUsed + " / " + hardwareSource.memoryTotal + " (" + hardwareSource.memoryPercent + ")"; color: ShellTheme.color("#aebdca"); font.pixelSize: 12 }
                    Rectangle {
                        width: parent.width
                        height: 28
                        color: ShellTheme.color("#263843")
                        Row {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            Text { width: 175; text: "Process"; color: ShellTheme.color("#bfeaff"); font.pixelSize: 11; font.bold: true; verticalAlignment: Text.AlignVCenter }
                            Text { width: 65; text: "RAM"; color: ShellTheme.color("#bfeaff"); font.pixelSize: 11; font.bold: true; verticalAlignment: Text.AlignVCenter }
                            Text { width: 90; text: "RSS"; color: ShellTheme.color("#bfeaff"); font.pixelSize: 11; font.bold: true; verticalAlignment: Text.AlignVCenter }
                            Text { width: 90; text: "VSZ"; color: ShellTheme.color("#bfeaff"); font.pixelSize: 11; font.bold: true; verticalAlignment: Text.AlignVCenter }
                            Text { width: 55; text: "CPU"; color: ShellTheme.color("#bfeaff"); font.pixelSize: 11; font.bold: true; verticalAlignment: Text.AlignVCenter }
                            Text { width: 70; text: "PID"; color: ShellTheme.color("#bfeaff"); font.pixelSize: 11; font.bold: true; verticalAlignment: Text.AlignVCenter }
                            Text { width: 100; text: "User / Time"; color: ShellTheme.color("#bfeaff"); font.pixelSize: 11; font.bold: true; verticalAlignment: Text.AlignVCenter }
                            Text { width: 85; text: "State"; color: ShellTheme.color("#bfeaff"); font.pixelSize: 11; font.bold: true; verticalAlignment: Text.AlignVCenter }
                            Text { width: parent.width - 730; text: "Command"; color: ShellTheme.color("#bfeaff"); font.pixelSize: 11; font.bold: true; verticalAlignment: Text.AlignVCenter }
                        }
                    }
                    Repeater {
                        model: hardwareSource.ramProcesses
                        delegate: Rectangle {
                            required property var modelData
                            width: ramColumn.width
                            height: 42
                            color: ShellTheme.color("#f21d2026")
                            MouseArea {
                                anchors.fill: parent
                                z: 1
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: detailsPopup.requestTermination(modelData)
                            }
                            Row {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                Text { width: 175; text: modelData.name; color: ShellTheme.color("#e8edf5"); font.pixelSize: 11; elide: Text.ElideRight; verticalAlignment: Text.AlignVCenter }
                                Text { width: 65; text: modelData.memory + "%"; color: ShellTheme.color("#d8d8d8"); font.pixelSize: 11; verticalAlignment: Text.AlignVCenter }
                                Text { width: 90; text: hardwareSource.formatKiB(modelData.rss); color: ShellTheme.color("#d8d8d8"); font.pixelSize: 10; verticalAlignment: Text.AlignVCenter }
                                Text { width: 90; text: hardwareSource.formatKiB(modelData.vsz); color: ShellTheme.color("#d8d8d8"); font.pixelSize: 10; verticalAlignment: Text.AlignVCenter }
                                Text { width: 55; text: modelData.cpu + "%"; color: ShellTheme.color("#d8d8d8"); font.pixelSize: 11; verticalAlignment: Text.AlignVCenter }
                                Text { width: 70; text: modelData.pid; color: ShellTheme.color("#d8d8d8"); font.pixelSize: 11; verticalAlignment: Text.AlignVCenter }
                                Text { width: 100; text: modelData.user + " / " + modelData.elapsed; color: ShellTheme.color("#d8d8d8"); font.pixelSize: 10; elide: Text.ElideRight; verticalAlignment: Text.AlignVCenter }
                                Text { width: 85; text: modelData.stat; color: ShellTheme.color("#d8d8d8"); font.pixelSize: 10; verticalAlignment: Text.AlignVCenter }
                                Text { width: parent.width - 730; text: modelData.command; color: ShellTheme.color("#b9c7d1"); font.pixelSize: 10; elide: Text.ElideRight; verticalAlignment: Text.AlignVCenter }
                            }
                        }
                    }
                }
            }

            Flickable {
                width: parent.width
                height: parent.height - 138
                contentWidth: width
                contentHeight: storageColumn.implicitHeight
                clip: true
                visible: detailsPopup.selectedTab === 3

                Column {
                    id: storageColumn
                    width: parent.width
                    spacing: 12

                    Text { text: "Storage devices"; color: ShellTheme.color("#8fb8ff"); font.pixelSize: 15; font.bold: true }
                    Repeater {
                        model: hardwareSource.storageDevices
                        delegate: Column {
                            required property var modelData
                            width: storageColumn.width
                            spacing: 7

                            Text { text: modelData.display + "  (" + modelData.path + ")"; color: ShellTheme.color("#e8edf5"); font.pixelSize: 14; font.bold: true; elide: Text.ElideRight; width: parent.width }
                            Text { text: modelData.type + "  |  " + modelData.medium + "  |  " + modelData.size + "  |  " + modelData.transport + "  |  " + modelData.mount + "  |  " + modelData.filesystem; color: ShellTheme.color("#aebdca"); font.pixelSize: 11; elide: Text.ElideRight; width: parent.width }
                            Rectangle {
                                width: parent.width
                                height: 28
                                color: ShellTheme.color("#263843")
                                Row {
                                    anchors.fill: parent
                                    anchors.leftMargin: 8
                                    anchors.rightMargin: 8
                                    Text { width: 170; text: "Process"; color: ShellTheme.color("#bfeaff"); font.pixelSize: 11; font.bold: true; verticalAlignment: Text.AlignVCenter }
                                    Text { width: 90; text: "Read/s"; color: ShellTheme.color("#bfeaff"); font.pixelSize: 11; font.bold: true; verticalAlignment: Text.AlignVCenter }
                                    Text { width: 90; text: "Write/s"; color: ShellTheme.color("#bfeaff"); font.pixelSize: 11; font.bold: true; verticalAlignment: Text.AlignVCenter }
                                    Text { width: 70; text: "PID"; color: ShellTheme.color("#bfeaff"); font.pixelSize: 11; font.bold: true; verticalAlignment: Text.AlignVCenter }
                                    Text { width: 65; text: "State"; color: ShellTheme.color("#bfeaff"); font.pixelSize: 11; font.bold: true; verticalAlignment: Text.AlignVCenter }
                                    Text { width: parent.width - 485; text: "Command"; color: ShellTheme.color("#bfeaff"); font.pixelSize: 11; font.bold: true; verticalAlignment: Text.AlignVCenter }
                                }
                            }
                            Repeater {
                                model: modelData.processes
                                delegate: Rectangle {
                                    required property var modelData
                                    width: storageColumn.width
                                    height: 42
                                    color: ShellTheme.color("#f21d2026")
                                    MouseArea {
                                        anchors.fill: parent
                                        z: 1
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: detailsPopup.requestTermination(modelData)
                                    }
                                    Row {
                                        anchors.fill: parent
                                        anchors.leftMargin: 8
                                        anchors.rightMargin: 8
                                        Text { width: 170; text: modelData.name; color: ShellTheme.color("#e8edf5"); font.pixelSize: 11; elide: Text.ElideRight; verticalAlignment: Text.AlignVCenter }
                                        Text { width: 90; text: modelData.readRate; color: ShellTheme.color("#d8d8d8"); font.pixelSize: 10; verticalAlignment: Text.AlignVCenter }
                                        Text { width: 90; text: modelData.writeRate; color: ShellTheme.color("#d8d8d8"); font.pixelSize: 10; verticalAlignment: Text.AlignVCenter }
                                        Text { width: 70; text: modelData.pid; color: ShellTheme.color("#d8d8d8"); font.pixelSize: 11; verticalAlignment: Text.AlignVCenter }
                                        Text { width: 65; text: modelData.state; color: ShellTheme.color("#d8d8d8"); font.pixelSize: 10; verticalAlignment: Text.AlignVCenter }
                                        Text { width: parent.width - 485; text: modelData.command; color: ShellTheme.color("#b9c7d1"); font.pixelSize: 10; elide: Text.ElideRight; verticalAlignment: Text.AlignVCenter }
                                    }
                                }
                            }
                        }
                    }
                }
            }

        }
    }

    Rectangle {
        anchors.fill: parent
        visible: detailsPopup.terminationConfirmationVisible
        z: 200
        color: ShellTheme.color("#c9000000")
        MouseArea { anchors.fill: parent }

        Rectangle {
            width: Math.min(560, parent.width - 80)
            height: 250
            anchors.centerIn: parent
            radius: 10
            color: ShellTheme.color("#f21d2026")
            border.color: ShellTheme.color("#d36a6a")
            border.width: 1

            Column {
                anchors.fill: parent
                anchors.margins: 22
                spacing: 14

                Text {
                    text: "Terminate process?"
                    color: ShellTheme.color("#ffb4b4")
                    font.pixelSize: 20
                    font.bold: true
                }
                Text {
                    width: parent.width
                    text: detailsPopup.selectedProcess
                        ? detailsPopup.selectedProcess.name + "  (PID " + detailsPopup.selectedProcess.pid + ")"
                        : "No process selected"
                    color: ShellTheme.color("#e8edf5")
                    font.pixelSize: 15
                    font.bold: true
                    elide: Text.ElideRight
                }
                Text {
                    width: parent.width
                    text: detailsPopup.terminationStatus.length > 0
                        ? detailsPopup.terminationStatus
                        : "This sends SIGTERM, allowing the process to exit cleanly. The PID and process name are rechecked immediately before signaling."
                    color: detailsPopup.terminationStatus.length > 0 ? ShellTheme.color("#c6e48b") : ShellTheme.color("#aebdca")
                    font.pixelSize: 13
                    wrapMode: Text.Wrap
                }
                Row {
                    width: parent.width
                    spacing: 10
                    layoutDirection: Qt.RightToLeft

                    Rectangle {
                        width: 150
                        height: 38
                        radius: 6
                        visible: detailsPopup.terminationStatus.length === 0
                        color: detailsPopup.terminationInProgress ? ShellTheme.color("#4b3030") : (killMouse.containsMouse ? ShellTheme.color("#8b3434") : ShellTheme.color("#6d2828"))
                        border.color: ShellTheme.color("#ee8c8c")
                        Text { anchors.centerIn: parent; text: detailsPopup.terminationInProgress ? "Terminating…" : "Kill (SIGTERM)"; color: ShellTheme.color("#ffffff"); font.pixelSize: 13; font.bold: true }
                        MouseArea {
                            id: killMouse
                            anchors.fill: parent
                            hoverEnabled: !detailsPopup.terminationInProgress
                            enabled: !detailsPopup.terminationInProgress
                            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: detailsPopup.confirmTermination()
                        }
                    }
                    Rectangle {
                        width: 100
                        height: 38
                        radius: 6
                        color: cancelMouse.containsMouse ? ShellTheme.color("#39424e") : ShellTheme.color("#2b323b")
                        border.color: ShellTheme.color("#7188aa")
                        Text { anchors.centerIn: parent; text: detailsPopup.terminationStatus.length > 0 ? "Close" : "Cancel"; color: ShellTheme.color("#e8edf5"); font.pixelSize: 13; font.bold: true }
                        MouseArea {
                            id: cancelMouse
                            anchors.fill: parent
                            hoverEnabled: !detailsPopup.terminationInProgress
                            enabled: !detailsPopup.terminationInProgress
                            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: detailsPopup.cancelTermination()
                        }
                    }
                }
            }
        }
    }
}
