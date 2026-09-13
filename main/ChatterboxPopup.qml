import QtQuick
import Quickshell
import "ShellTheme.js" as ShellTheme

LifecyclePopup {
    property var barWindow
    readonly property string chatterboxDir: Quickshell.env("CHATTERBOX_DIR") || ((Quickshell.env("HOME") || "") + "/Work/AI_Dev/Chatterbox")
    readonly property string chatterboxNvidiaDir: Quickshell.env("CHATTERBOX_NVIDIA_DIR") || ((Quickshell.env("HOME") || "") + "/Work/AI_Dev/Chatterbox-NVIDIA")

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
        color: ShellTheme.color("#f0262626")
        border.color: ShellTheme.color("#555555")
        border.width: 1

        Column {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 6

            Text {
                width: parent.width
                height: 28
                text: "Hermes Chatterbox"
                color: ShellTheme.color("#9be9a8")
                font.bold: true
                font.pixelSize: 14
                verticalAlignment: Text.AlignVCenter
            }

            Rectangle {
                width: parent.width
                height: 40
                radius: 5
                color: stopMouse.containsMouse ? ShellTheme.color("#553f3f") : "transparent"

                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    text: "󰈆  End Chatterbox process"
                    color: ShellTheme.color("#ffb4b4")
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
                            "target=$(ps -eo pid=,pgid=,args= | awk '/python/ && (index($0, \"" + chatterboxDir + "/start.py --rocm\") || index($0, \"" + chatterboxNvidiaDir + "/start.py --nvidia\")) {print $1, $2; exit}'); " +
                            "set -- $target; [ -n \"$2\" ] && kill -TERM -- -\"$2\""
                        ])
                        lifecycleOwner.close()
                    }
                    cursorShape: Qt.PointingHandCursor
                }
            }
        }
    }
}
