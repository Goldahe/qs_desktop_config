import QtQuick
import Quickshell

PopupWindow {
    property var barWindow

    anchor.window: barWindow
    anchor.rect.x: barWindow.chatterboxPopupX() + 115
    anchor.rect.y: barWindow.height - barWindow.taskbarHeight - 3
    anchor.gravity: Edges.Top
    implicitWidth: 240
    implicitHeight: 104
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

            Text {
                width: parent.width
                height: 28
                text: "Hermes Chatterbox"
                color: "#9be9a8"
                font.bold: true
                font.pixelSize: 14
                verticalAlignment: Text.AlignVCenter
            }

            Rectangle {
                width: parent.width
                height: 40
                radius: 5
                color: stopMouse.containsMouse ? "#553f3f" : "transparent"

                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    text: "󰈆  End Chatterbox process"
                    color: "#ffb4b4"
                    font.family: "Symbols Nerd Font"
                    font.pixelSize: 13
                }

                MouseArea {
                    id: stopMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        Quickshell.execDetached([
                            "sh", "-c",
                            "target=$(ps -eo pid=,pgid=,args= | awk '/python/ && (index($0, \"/home/hawk/Work/AI_Dev/Chatterbox/start.py --rocm\") || index($0, \"/home/hawk/Work/AI_Dev/Chatterbox-NVIDIA/start.py --nvidia\")) {print $1, $2; exit}'); " +
                            "set -- $target; [ -n \"$2\" ] && kill -TERM -- -\"$2\""
                        ])
                        barWindow.chatterboxMenu.visible = false
                    }
                    cursorShape: Qt.PointingHandCursor
                }
            }
        }
    }
}
