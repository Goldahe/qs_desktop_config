import QtQuick
import Quickshell
import Quickshell.Networking

PopupWindow {
    property var barWindow

    anchor.window: barWindow
    anchor.rect.x: barWindow.width - width - 115
    anchor.rect.y: barWindow.height - barWindow.taskbarHeight
    anchor.gravity: Edges.Top | Edges.Right
    implicitWidth: 280
    implicitHeight: Math.max(100, Math.min(360, (barWindow.wifiDevice ? barWindow.wifiDevice.networks.values.length : 0) * 44 + 58))
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
                text: barWindow.wifiDevice && barWindow.wifiDevice.connected
                      ? "Wi-Fi: " + barWindow.wifiDevice.name
                      : "Wi-Fi networks"
                color: "white"
                font.pixelSize: 14
                font.bold: true
            }

            Repeater {
                model: barWindow.wifiDevice ? barWindow.wifiDevice.networks : null

                delegate: Rectangle {
                    required property var modelData
                    width: parent.width
                    height: 36
                    radius: 5
                    color: wifiMouse.containsMouse ? "#454545" : "transparent"

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        text: (modelData.connected ? "● " : "○ ") + modelData.name
                              + (modelData.security !== WifiSecurityType.Open ? " 󰌾" : "")
                        color: modelData.connected ? "white" : "#d0d0d0"
                        font.family: "Symbols Nerd Font"
                        font.pixelSize: 13
                        elide: Text.ElideRight
                        width: parent.width - 16
                    }

                    MouseArea {
                        id: wifiMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: barWindow.connectWifi(modelData)
                        cursorShape: Qt.PointingHandCursor
                    }
                }
            }

            Text {
                visible: !barWindow.wifiDevice || barWindow.wifiDevice.networks.values.length === 0
                text: "No networks found"
                color: "#858585"
                font.pixelSize: 13
            }
        }
    }
}
