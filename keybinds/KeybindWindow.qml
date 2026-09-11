import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io

FloatingWindow {
    id: window

    title: "Configured Keybinds"
    implicitWidth: 820
    readonly property int targetHeight: Math.floor((screen ? screen.height : 900) * 0.75)
    implicitHeight: targetHeight
    color: "#0d141b"
    visible: true

    property var bindRows: []
    property string filterText: ""
    property string loadError: ""

    function modifierText(mask) {
        const names = []
        if (mask & 1) names.push("SHIFT")
        if (mask & 4) names.push("CTRL")
        if (mask & 8) names.push("ALT")
        if (mask & 64) names.push("SUPER")
        return names.join(" + ")
    }

    function keyText(bind) {
        const key = String(bind.key || bind.keycode || "?")
        const modifiers = modifierText(Number(bind.modmask || 0))
        return modifiers ? modifiers + " + " + key : key
    }

    // Edit this function to change the human-readable text shown for each bind.
    function manualDescription(bind, occurrence) {
        const key = String(bind.key || "")
        const mask = Number(bind.modmask || 0)

        if (mask === 64 && key === "Q") return "Opens Kitty terminal"
        if (mask === 64 && key === "C") return "Closes the focused window"
        if (mask === 64 && key === "Escape") return "Shuts down Hyprland"
        if (mask === 64 && key === "E") return "Opens Dolphin file manager"
        if (mask === 64 && key === "V") return "Toggles floating mode for the focused window"
        if (mask === 64 && key === "R") return "Opens the application launcher"
        if (mask === 64 && key === "P") return "Toggles pseudo-tile mode"
        if (mask === 64 && key === "J") return "Toggles the dwindle split direction"
        if (mask === 64 && key === "I") return "Opens the web browser"
        if (mask === 64 && key === "W") return "Toggles fullscreen mode"
        if (mask === 64 && key === "B") return "Opens Blender"
        if (mask === 64 && key === "K") return "Opens Krita"
        if (mask === 64 && key === "M") return "Opens Minecraft"
        if (mask === 64 && key === "S") return "Opens Steam"
        if (mask === 65 && key === "H") return "Opens Hermes Agent"
        if (mask === 65 && key === "V") return "Toggles the RTX 2080 VFIO/host mode"
        if (mask === 64 && key === "A") return "Opens the HK-47 agent selector"
        if (mask === 64 && key === "SLASH") return "Opens this keybind reference"
        if (mask === 64 && key === "left") return "Moves focus to the window on the left"
        if (mask === 64 && key === "right") return "Moves focus to the window on the right"
        if (mask === 64 && key === "up") return "Moves focus to the window above"
        if (mask === 64 && key === "down") return "Moves focus to the window below"
        if (key === "mouse_down" && mask === 64) return "Switches to the next workspace"
        if (key === "mouse_up" && mask === 64) return "Switches to the previous workspace"
        if (key === "mouse:272" && mask === 64) return "Drags the focused window"
        if (key === "mouse:273" && mask === 64) return "Resizes the focused window"
        if (key === "PRINT" && mask === 64) return "Captures the entire screen"
        if (key === "S" && mask === 69) return "Captures a selected region and copies it"
        if (key === "S" && mask === 65) return "Moves the focused window to the special workspace"
        if (key === "S" && mask === 72) return "Toggles the magic special workspace"
        if (key === "XF86AudioRaiseVolume") return "Raises the system volume"
        if (key === "XF86AudioLowerVolume") return "Lowers the system volume"
        if (key === "XF86AudioMute") return "Toggles system mute"
        if (key === "XF86AudioMicMute") return "Toggles microphone mute"
        if (key === "XF86MonBrightnessUp") return "Raises screen brightness"
        if (key === "XF86MonBrightnessDown") return "Lowers screen brightness"
        if (key === "XF86AudioNext") return "Skips to the next media track"
        if (key === "XF86AudioPause" || key === "XF86AudioPlay") return "Toggles media playback"
        if (key === "XF86AudioPrev") return "Returns to the previous media track"
        if (/^[0-9]$/.test(key) && mask === 64) return "Switches to workspace " + (key === "0" ? "10" : key)
        if (/^[0-9]$/.test(key) && mask === 65) return "Moves the focused window to workspace " + (key === "0" ? "10" : key)
        return "Custom binding; edit manualDescription() to label it"
    }

    function actionText(bind, occurrence) {
        return manualDescription(bind, occurrence)
    }

    function rebuildModel() {
        displayModel.clear()
        const needle = filterText.trim().toLowerCase()
        const seen = ({})
        for (const bind of bindRows) {
            const identity = String(bind.modmask || 0) + "|" + String(bind.key || "")
            const occurrence = seen[identity] || 0
            seen[identity] = occurrence + 1
            const row = {
                key: keyText(bind),
                action: actionText(bind, occurrence),
                description: String(bind.description || ""),
                source: bind
            }
            const haystack = (row.key + " " + row.action + " " + row.description).toLowerCase()
            if (!needle || haystack.indexOf(needle) >= 0)
                displayModel.append(row)
        }
        window.implicitHeight = window.targetHeight
    }

    function parseBinds(text) {
        try {
            const parsed = JSON.parse(text || "[]")
            bindRows = Array.isArray(parsed) ? parsed : []
            loadError = ""
            rebuildModel()
        } catch (error) {
            bindRows = []
            loadError = "Unable to parse hyprctl binds -j output"
            rebuildModel()
        }
    }

    function closeWindow() {
        window.visible = false
        Qt.callLater(Qt.quit)
    }

    ListModel { id: displayModel }

    Process {
        id: bindsReader
        command: ["hyprctl", "binds", "-j"]
        running: true
        stdout: StdioCollector { id: bindsOutput }
        stderr: StdioCollector { id: bindsError }
        onExited: function(exitCode) {
            if (exitCode === 0)
                window.parseBinds(bindsOutput.text)
            else {
                window.loadError = bindsError.text || "hyprctl binds -j failed"
                window.rebuildModel()
            }
        }
    }

    Shortcut {
        sequence: "Escape"
        enabled: window.visible
        onActivated: window.closeWindow()
    }

    onVisibleChanged: {
        if (!visible)
            Qt.callLater(Qt.quit)
    }

    Rectangle {
        anchors.fill: parent
        color: "#0d141b"
        border.width: 1
        border.color: "#31596b"
        radius: 10

        Column {
            anchors.fill: parent
            anchors.margins: 18
            spacing: 12

            Row {
                width: parent.width
                height: 34
                spacing: 12

                Text {
                    width: parent.width - countLabel.width - parent.spacing
                    text: "CONFIGURED KEYBINDS"
                    color: "#bcecff"
                    font.bold: true
                    font.pixelSize: 18
                    verticalAlignment: Text.AlignVCenter
                }

                Text {
                    id: countLabel
                    text: displayModel.count + " shown / " + window.bindRows.length + " registered"
                    color: "#79b9ce"
                    font.pixelSize: 12
                    verticalAlignment: Text.AlignVCenter
                }
            }

            Text {
                width: parent.width
                text: "Live compositor bindings · Escape closes"
                color: "#6d8995"
                font.pixelSize: 11
            }

            TextField {
                id: searchField
                width: parent.width
                height: 38
                placeholderText: "Filter by key, dispatcher, argument, or description"
                color: "#d8f4ff"
                placeholderTextColor: "#66818d"
                font.pixelSize: 13
                background: Rectangle {
                    radius: 6
                    color: "#14232c"
                    border.width: 1
                    border.color: searchField.activeFocus ? "#62b9d6" : "#294854"
                }
                onTextChanged: {
                    window.filterText = text
                    window.rebuildModel()
                }
            }

            Rectangle {
                width: parent.width
                height: 1
                color: "#24404c"
            }

            Text {
                visible: window.loadError !== ""
                width: parent.width
                text: window.loadError
                color: "#ff8d8d"
                wrapMode: Text.Wrap
            }

            ListView {
                id: bindList
                width: parent.width
                height: parent.height - 132
                clip: true
                spacing: 5
                model: displayModel
                ScrollBar.vertical: ScrollBar {}

                delegate: Rectangle {
                    required property int index
                    required property string key
                    required property string action
                    required property string description
                    width: bindList.width - 12
                    height: 37
                    radius: 5
                    color: index % 2 === 0 ? "#12212a" : "#101c23"
                    border.width: 1
                    border.color: "#1d3945"

                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 12

                        Text {
                            width: 190
                            height: parent.height
                            text: key
                            color: "#8fddf3"
                            font.bold: true
                            font.pixelSize: 12
                            verticalAlignment: Text.AlignVCenter
                            elide: Text.ElideRight
                        }

                        Text {
                            width: parent.width - 202
                            height: parent.height
                            text: description !== "" ? action + "  ·  " + description : action
                            color: "#c3d6dc"
                            font.pixelSize: 12
                            verticalAlignment: Text.AlignVCenter
                            elide: Text.ElideRight
                        }
                    }
                }
            }
        }
    }
}
