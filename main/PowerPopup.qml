import QtQuick
import Quickshell

PopupWindow {
    property var barWindow

    anchor.window: barWindow
    anchor.rect.x: barWindow.width - width - 10
    anchor.rect.y: barWindow.height - barWindow.taskbarHeight
    anchor.gravity: Edges.Top | Edges.Right
    implicitWidth: 170
    implicitHeight: 156
    color: "transparent"
    visible: false
    grabFocus: true

    Rectangle {
        anchors.fill: parent
        radius: 8
        color: "#f0262626"
        border.color: "#555555"
        border.width: 1

        Column {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 6

            Repeater {
                model: [
                    { label: "  Shutdown", command: "systemctl poweroff" },
                    { label: "  Reboot", command: "systemctl reboot" },
                    { label: "  Logout", command: "loginctl terminate-user \"$USER\"" }
                ]

                delegate: Rectangle {
                    required property var modelData
                    width: parent.width
                    height: 38
                    radius: 5
                    color: actionMouse.containsMouse ? "#454545" : "transparent"

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.label
                        color: "white"
                        font.family: "Symbols Nerd Font"
                        font.pixelSize: 14
                    }

                    MouseArea {
                        id: actionMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: barWindow.powerAction(modelData.command)
                        cursorShape: Qt.PointingHandCursor
                    }
                }
            }
        }
    }
}
