import QtQuick
import "ShellTheme.js" as ShellTheme

Rectangle {
    id: llmButton
    property var barWindow
    width: 30
    height: 28
    radius: 5
    color: llmMouse.containsMouse ? ShellTheme.color("#454545") : "transparent"

    Text {
        anchors.centerIn: parent
        text: "󰚩"
        color: ShellTheme.color("#ffffff")
        font.family: "Symbols Nerd Font"
        font.pixelSize: 17
    }

    MouseArea {
        id: llmMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: barWindow.togglePopup("llm", true)
    }
}
