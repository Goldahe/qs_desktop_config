import QtQuick
import Quickshell
import "ShellTheme.js" as ShellTheme

Rectangle {
    property var barWindow

    width: 30
    height: 28
    radius: 5
    color: hardwareMouse.containsMouse ? ShellTheme.color("#454545") : "transparent"

    Text {
        anchors.centerIn: parent
        text: "󰍛"
        color: ShellTheme.color("#ffffff")
        font.family: "Symbols Nerd Font"
        font.pixelSize: 16
    }

    MouseArea {
        id: hardwareMouse
        anchors.fill: parent
        hoverEnabled: true
        onClicked: barWindow.toggleHardware()
        cursorShape: Qt.PointingHandCursor
    }
}
