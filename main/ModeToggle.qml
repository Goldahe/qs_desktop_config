import QtQuick
import Quickshell
import "ShellTheme.js" as ShellTheme

Rectangle {
    id: modeToggle
    property var barWindow

    width: 30
    height: 28
    radius: 5
    color: modeMouse.containsMouse
        ? (barWindow.gameMode ? ShellTheme.color("#59483a") : ShellTheme.color("#304f38"))
        : "transparent"

    Text {
        anchors.centerIn: parent
        text: barWindow.gameMode ? "󰊗" : "󰖷"
        color: barWindow.gameMode ? ShellTheme.color("#ffd28a") : ShellTheme.color("#9be9a8")
        font.family: "Symbols Nerd Font"
        font.pixelSize: 17
    }

    MouseArea {
        id: modeMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: barWindow.setGameMode(!barWindow.gameMode)
    }
}
