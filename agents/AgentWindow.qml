import QtQuick
import QtQuick.Controls
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io

FloatingWindow {
    id: agentWindow

    title: "HK-47 Agent Selector"
    implicitWidth: 560
    readonly property int maximumWindowHeight: Math.max(220, Math.floor((screen ? screen.height : 900) * 0.5))
    readonly property int bottomBuffer: 20
    readonly property int listOverhead: 132
    readonly property int rowHeight: 92
    readonly property int rowStride: rowHeight + 7
    readonly property int desiredHeight: Math.min(maximumWindowHeight,
                                                  Math.max(220, listOverhead + agentModel.length * rowStride + bottomBuffer))
    implicitHeight: 220
    color: "#101820"
    visible: rosterLoaded

    onVisibleChanged: {
        if (!visible && rosterLoaded)
            Qt.callLater(agentWindow.terminateProfile)
    }

    property var agentModel: []
    property string rosterText: ""
    property bool rosterLoaded: false
    property var agentPathOverrides: ({})
    property var sessionPaths: ({})
    property var savePathEnabled: ({})
    property string rosterPayload: ""
    property var pendingAgent: null
    property url selectedFolderUrl: ""
    readonly property string rosterPath: Qt.resolvedUrl("agents.json").toString().replace("file://", "")
    readonly property string homeDir: Quickshell.env("HOME") || ""
    readonly property string defaultPath: homeDir + "/"

    function expandHome(path) {
        const value = String(path || "")
        return value.indexOf("$HOME") === 0 ? homeDir + value.substring(5) : value
    }

    function collapseHome(path) {
        const value = String(path || "")
        return homeDir && value.indexOf(homeDir) === 0 ? "$HOME" + value.substring(homeDir.length) : value
    }

    function showSizedWindow() {
        agentWindow.implicitHeight = agentWindow.desiredHeight
        agentWindow.rosterLoaded = true
    }

    function terminateProfile() {
        Qt.quit()
    }

    function loadRoster() {
        try {
            const parsed = JSON.parse(rosterText || "{}")
            agentModel = Array.isArray(parsed.agents) ? parsed.agents : []
            const saved = {}
            for (const agent of agentModel) {
                if (agent.path && String(agent.path).trim())
                    saved[agentKey(agent)] = String(agent.path)
            }
            agentPathOverrides = saved
        } catch (error) {
            agentModel = []
            agentPathOverrides = ({})
        }
    }

    function agentKey(agent) {
        return String(agent && agent.name ? agent.name : agent && agent.command ? agent.command : "unknown")
    }

    function overrideEnabled(agent) {
        return !!savePathEnabled[agentKey(agent)]
    }

    function overridePath(agent) {
        const key = agentKey(agent)
        return agentWindow.expandHome(sessionPaths[key] || agentPathOverrides[key] || agentWindow.defaultPath)
    }

    function setOverride(agent, enabled) {
        const key = agentKey(agent)
        const updated = Object.assign({}, savePathEnabled)
        updated[key] = enabled
        savePathEnabled = updated
        if (enabled && sessionPaths[key])
            saveAgentPath(agent, sessionPaths[key])
    }

    function openPathSelector(agent) {
        pendingAgent = agent
        folderModel.folder = "file://" + agentWindow.defaultPath
        selectedFolderUrl = ""
        pathPopup.open()
    }

    function selectedPathFromUrl(url) {
        let path = String(url || "")
        if (path.indexOf("file://") === 0)
            path = path.substring(7)
        try {
            return decodeURIComponent(path)
        } catch (error) {
            return path
        }
    }

    function acceptSelectedPath(url) {
        if (!pendingAgent)
            return
        const key = agentKey(pendingAgent)
        const selectedPath = selectedPathFromUrl(url) || agentWindow.defaultPath
        const updated = Object.assign({}, sessionPaths)
        updated[key] = selectedPath
        sessionPaths = updated
        if (overrideEnabled(pendingAgent))
            saveAgentPath(pendingAgent, selectedPath)
        pendingAgent = null
    }

    function saveAgentPath(agent, path) {
        const key = agentKey(agent)
        const updated = agentModel.map(function(entry) {
            const copy = Object.assign({}, entry)
            if (agentKey(copy) === key)
                copy.path = agentWindow.collapseHome(path)
            return copy
        })
        agentModel = updated
        rosterPayload = JSON.stringify({ agents: updated }, null, 2) + "\n"
        rosterWriter.running = true
    }

    function shellQuote(value) {
        return "'" + String(value).replace(/'/g, "'\\''") + "'"
    }

    function launchAgent(agent) {
        if (!agent || !agent.command || !String(agent.command).trim())
            return
        const workingPath = overridePath(agent)
        const inheritedPath = Quickshell.env("PATH") || ""
        const launchPath = agentWindow.homeDir + "/.local/bin:" + inheritedPath
        const command = "export PATH=" + shellQuote(launchPath) + " && cd -- " + shellQuote(workingPath) + " && " + String(agent.command)
        if (agent.terminal === false)
            Quickshell.execDetached(["sh", "-lc", command])
        else
            Quickshell.execDetached(["kitty", "-e", "sh", "-lc", command])
        terminateProfile()
    }

    Process {
        id: rosterReader
        command: ["cat", agentWindow.rosterPath]
        running: true
        stdout: StdioCollector { id: rosterOutput }
        onExited: function(exitCode) {
            agentWindow.rosterText = exitCode === 0 ? rosterOutput.text : ""
            agentWindow.loadRoster()
            Qt.callLater(agentWindow.showSizedWindow)
        }
    }

    Process {
        id: rosterWriter
        command: ["python3", "-c", "import os,sys,tempfile; p=sys.argv[1]; d=sys.argv[2]; fd,t=tempfile.mkstemp(prefix='.agents.',dir=os.path.dirname(p)); f=os.fdopen(fd,'w'); f.write(d); f.flush(); os.fsync(f.fileno()); f.close(); os.replace(t,p)", agentWindow.rosterPath, agentWindow.rosterPayload]
        running: false
    }

    FolderListModel {
        id: folderModel
        showFiles: false
        showDirs: true
        showDirsFirst: true
        showHidden: true
        sortField: FolderListModel.Name
    }

    Popup {
        id: pathPopup
        x: Math.round((agentWindow.width - width) / 2)
        y: Math.round((agentWindow.height - height) / 2)
        width: Math.min(500, agentWindow.width - 32)
        height: Math.min(400, agentWindow.height - 32)
        modal: true
        focus: true
        closePolicy: Popup.NoAutoClose

        Overlay.modal: Rectangle { color: "#990b1217" }
        background: Rectangle {
            radius: 10
            color: "#101820"
            border.width: 1
            border.color: "#62b9d6"
        }

        Column {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 9

            Row {
                width: parent.width
                height: 28

                Text {
                    width: parent.width
                    text: "SELECT SESSION PATH"
                    color: "#bcecff"
                    font.bold: true
                    font.pixelSize: 14
                    verticalAlignment: Text.AlignVCenter
                }
            }

            Text {
                width: parent.width
                text: agentWindow.selectedPathFromUrl(folderModel.folder)
                color: "#87a8b8"
                font.pixelSize: 11
                elide: Text.ElideMiddle
            }

            Button {
                width: parent.width
                height: 30
                text: "..  UP ONE DIRECTORY"
                enabled: String(folderModel.folder) !== "file:///"
                onClicked: folderModel.folder = folderModel.parentFolder
                background: Rectangle {
                    radius: 5
                    color: parent.enabled ? (parent.down ? "#183e4c" : parent.hovered ? "#3b88a3" : "#245a6d") : "#172a34"
                    border.width: 1
                    border.color: parent.enabled ? "#4e9bb5" : "#31505e"
                }
                contentItem: Text {
                    text: parent.text
                    color: parent.enabled ? "#d8f5ff" : "#607783"
                    font.pixelSize: 11
                    horizontalAlignment: Text.AlignLeft
                    verticalAlignment: Text.AlignVCenter
                    leftPadding: 10
                }
            }

            ListView {
                id: folderList
                width: parent.width
                height: parent.height - 28 - 30 - 30 - 18 - 30
                clip: true
                spacing: 4
                model: folderModel
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                delegate: Rectangle {
                    required property string fileName
                    required property url fileUrl
                    width: folderList.width
                    height: 32
                    radius: 5
                    color: folderMouse.containsMouse || String(agentWindow.selectedFolderUrl) === String(fileUrl) ? "#24485a" : "#182a34"
                    border.width: 1
                    border.color: folderMouse.containsMouse || String(agentWindow.selectedFolderUrl) === String(fileUrl) ? "#62b9d6" : "#31505e"

                    Text {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        text: "▸  " + fileName
                        color: "#d8f5ff"
                        font.pixelSize: 12
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                    }

                    MouseArea {
                        id: folderMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: agentWindow.selectedFolderUrl = fileUrl
                        onDoubleClicked: folderModel.folder = fileUrl
                    }
                }
            }

            Row {
                width: parent.width
                height: 30
                spacing: 8

                Button {
                    width: (parent.width - parent.spacing) / 2
                    height: 34
                    text: "SELECT PATH"
                    onClicked: {
                        agentWindow.acceptSelectedPath(agentWindow.selectedFolderUrl || folderModel.folder)
                        pathPopup.close()
                    }
                    background: Rectangle {
                        radius: 5
                        color: parent.down ? "#183e4c" : parent.hovered ? "#3b88a3" : "#245a6d"
                        border.width: 1
                        border.color: "#62b9d6"
                    }
                    contentItem: Text {
                        text: parent.text
                        color: "#d8f5ff"
                        font.bold: true
                        font.pixelSize: 11
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                }

                Button {
                    width: (parent.width - parent.spacing) / 2
                    height: 34
                    text: "CANCEL"
                    onClicked: {
                        agentWindow.pendingAgent = null
                        pathPopup.close()
                    }
                    background: Rectangle {
                        radius: 5
                        color: parent.down ? "#183e4c" : parent.hovered ? "#24485a" : "#172a34"
                        border.width: 1
                        border.color: "#4e7788"
                    }
                    contentItem: Text {
                        text: parent.text
                        color: "#a9c4cf"
                        font.pixelSize: 11
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                }
            }
        }
    }

    Shortcut {
        sequence: "Escape"
        onActivated: agentWindow.terminateProfile()
    }

    Rectangle {
        anchors.fill: parent
        radius: 10
        color: "#101820"
        border.width: 1
        border.color: "#3d687c"

        Column {
            anchors.fill: parent
            anchors.margins: 18
            spacing: 10

            Row {
                width: parent.width
                height: 30

                Text {
                    width: parent.width
                    text: "AGENT DEPLOYMENT"
                    color: "#bcecff"
                    font.family: "Symbols Nerd Font"
                    font.bold: true
                    font.pixelSize: 16
                    verticalAlignment: Text.AlignVCenter
                }
            }

            Text {
                width: parent.width
                text: agentWindow.agentModel.length === 0
                    ? "No agents configured. Edit agents.json to populate this roster."
                    : "Select an agent. Use > to choose a session directory, then enable Override."
                color: "#8ea7b5"
                font.pixelSize: 12
                wrapMode: Text.WordWrap
            }

            ListView {
                width: parent.width
                height: Math.min(contentHeight,
                                 Math.max(agentWindow.rowHeight, agentWindow.maximumWindowHeight -
                                          agentWindow.listOverhead - agentWindow.bottomBuffer))
                clip: true
                spacing: 7
                model: agentWindow.agentModel

                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    width: ListView.view.width
                    height: agentWindow.rowHeight
                    radius: 6
                    color: agentMouse.containsMouse ? "#24485a" : "#182a34"
                    border.width: 1
                    border.color: agentMouse.containsMouse ? "#76c8e8" : "#31505e"

                    MouseArea {
                        id: agentMouse
                        anchors.fill: parent
                        z: 0
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: agentWindow.launchAgent(modelData)
                    }

                    Row {
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 12
                        z: 1

                        Rectangle {
                            width: 54
                            height: 54
                            radius: 7
                            anchors.verticalCenter: parent.verticalCenter
                            color: "#213b48"
                            border.width: 1
                            border.color: "#4e7788"

                            Image {
                                id: iconImage
                                anchors.fill: parent
                                anchors.margins: 3
                                source: agentWindow.expandHome(modelData.icon || "")
                                asynchronous: true
                                fillMode: Image.PreserveAspectFit
                                smooth: true
                            }

                            Text {
                                anchors.centerIn: parent
                                text: (modelData.name || "?").substring(0, 1).toUpperCase()
                                color: "#bcecff"
                                font.bold: true
                                font.pixelSize: 23
                                visible: iconImage.status !== Image.Ready
                            }
                        }

                        Column {
                            width: parent.width - 66 - 62
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 3

                            Text {
                                width: parent.width
                                text: modelData.name || "Unnamed agent"
                                color: "#d8f5ff"
                                font.bold: true
                                font.pixelSize: 14
                                elide: Text.ElideRight
                            }

                            Text {
                                width: parent.width
                                text: modelData.description || modelData.command || "No command configured"
                                color: "#87a8b8"
                                font.pixelSize: 11
                                elide: Text.ElideMiddle
                            }

                            Text {
                                width: parent.width
                                text: "Path: " + agentWindow.overridePath(modelData)
                                color: agentWindow.overridePath(modelData) !== agentWindow.defaultPath ? "#a7d8a1" : "#718b96"
                                font.pixelSize: 10
                                elide: Text.ElideMiddle
                            }
                        }

                        Column {
                            width: 62
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 3

                            Button {
                                id: pathButton
                                width: 44
                                height: 28
                                text: ">"
                                font.bold: true
                                font.pixelSize: 17
                                background: Rectangle {
                                    radius: 5
                                    color: pathButton.down ? "#183e4c" : pathButton.hovered ? "#3b88a3" : "#245a6d"
                                    border.width: 1
                                    border.color: "#62b9d6"
                                }
                                contentItem: Text {
                                    text: pathButton.text
                                    color: "#d8f5ff"
                                    font: pathButton.font
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                                ToolTip.visible: hovered
                                ToolTip.text: "Choose a session path"
                                onClicked: agentWindow.openPathSelector(modelData)
                            }

                            CheckBox {
                                id: overrideCheck
                                width: 62
                                height: 24
                                checked: agentWindow.overrideEnabled(modelData)
                                text: "Save"
                                spacing: 4
                                contentItem: Text {
                                    text: overrideCheck.text
                                    color: "#a9dceb"
                                    font.pixelSize: 10
                                    verticalAlignment: Text.AlignVCenter
                                    leftPadding: 15
                                }
                                indicator: Rectangle {
                                    x: 0
                                    y: (overrideCheck.height - height) / 2
                                    width: 16
                                    height: 16
                                    radius: 3
                                    color: overrideCheck.checked ? "#58aeca" : "#172a34"
                                    border.width: 1
                                    border.color: overrideCheck.checked ? "#bcecff" : "#4e7788"
                                    Text {
                                        anchors.centerIn: parent
                                        text: "✓"
                                        color: "#0b1720"
                                        font.bold: true
                                        visible: overrideCheck.checked
                                    }
                                }
                                ToolTip.visible: hovered
                                ToolTip.text: "Save selected path as this agent's default"
                                onClicked: agentWindow.setOverride(modelData, checked)
                            }
                        }
                    }
                }
            }
        }
    }
}
