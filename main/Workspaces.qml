import QtQuick
import Quickshell.Hyprland

Row {
    anchors.left: parent.left
    anchors.leftMargin: 10
    anchors.verticalCenter: parent.verticalCenter
    spacing: 4

    Repeater {
        model: Hyprland.workspaces

        delegate: Rectangle {
            required property var modelData
            readonly property bool isFocused: modelData.focused
            readonly property bool isOccupied: modelData.toplevels.values.length > 0

            visible: isOccupied || isFocused
            width: label.implicitWidth + 16
            height: 28
            radius: 5
            color: isFocused ? "#3a3a3a" : "transparent"

            Text {
                id: label
                anchors.centerIn: parent
                text: modelData.name
                color: isFocused ? "white" : "#858585"
                font.pixelSize: 14
                font.bold: isFocused
            }

            MouseArea {
                anchors.fill: parent
                onClicked: modelData.activate()
                cursorShape: Qt.PointingHandCursor
            }
        }
    }
}
