import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import Quickshell.Bluetooth
import Quickshell.Services.SystemTray
import Quickshell.Widgets

Row {
    id: statusControls
    property var barWindow
    property var clock

    anchors.right: parent.right
    anchors.rightMargin: 10
    anchors.verticalCenter: parent.verticalCenter
    height: 28
    spacing: 14

    Repeater {
        model: SystemTray.items.values

        delegate: Item {
            required property var modelData
            width: 24
            height: 28

            IconImage {
                anchors.centerIn: parent
                width: 18
                height: 18
                source: modelData.icon
                asynchronous: true
                mipmap: true
            }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: function(mouse) {
                    if (mouse.button === Qt.LeftButton) {
                        if (modelData.onlyMenu || modelData.hasMenu)
                            modelData.display(barWindow, statusControls.x + x, statusControls.y)
                        else
                            modelData.activate()
                    } else if (mouse.button === Qt.RightButton) {
                        if (modelData.hasMenu)
                            modelData.display(barWindow, statusControls.x + x, statusControls.y)
                        else
                            modelData.secondaryActivate()
                    }
                }
            }
        }
    }

    Text {
        // Direct binding keeps updates reactive when PipeWire changes volume.
        text: {
            const sink = Pipewire.defaultAudioSink
            if (!sink || !sink.audio)
                return " --"
            if (sink.audio.muted)
                return "  muted"
            return " " + Math.round(sink.audio.volume * 100) + "%"
        }
        color: "white"
        font.family: "Symbols Nerd Font"
        font.pixelSize: 14
        height: parent.height
        verticalAlignment: Text.AlignVCenter
        MouseArea {
            anchors.fill: parent
            onClicked: Quickshell.execDetached(["pavucontrol"])
            cursorShape: Qt.PointingHandCursor
        }
    }

    Text {
        text: barWindow.bluetoothText()
        color: Bluetooth.defaultAdapter && Bluetooth.defaultAdapter.enabled ? "white" : "#858585"
        font.family: "Symbols Nerd Font"
        font.pixelSize: 14
        height: parent.height
        verticalAlignment: Text.AlignVCenter
        MouseArea {
            anchors.fill: parent
            onClicked: Quickshell.execDetached(["blueman-manager"])
            cursorShape: Qt.PointingHandCursor
        }
    }


    Text {
        text: Qt.formatDateTime(clock.date, "HH:mm")
        color: "white"
        font.pixelSize: 14
        font.bold: true
        height: parent.height
        verticalAlignment: Text.AlignVCenter
    }

    Text {
        text: Qt.formatDateTime(clock.date, "ddd, dd MMM")
        color: "#c8c8c8"
        font.pixelSize: 13
        height: parent.height
        verticalAlignment: Text.AlignVCenter
        MouseArea {
            anchors.fill: parent
            onClicked: barWindow.openCalendar()
            cursorShape: Qt.PointingHandCursor
        }
    }

    Rectangle {
        width: 28
        height: 28
        radius: 5
        color: powerMouse.containsMouse ? "#553f3f" : "transparent"

        Text {
            anchors.centerIn: parent
            text: ""
            color: "#ffb4b4"
            font.family: "Symbols Nerd Font"
            font.pixelSize: 16
        }

        MouseArea {
            id: powerMouse
            anchors.fill: parent
            hoverEnabled: true
            onClicked: barWindow.powerMenu.visible = !barWindow.powerMenu.visible
            cursorShape: Qt.PointingHandCursor
        }
    }
}
