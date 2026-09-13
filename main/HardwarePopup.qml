import QtQuick
import Quickshell
import "ShellTheme.js" as ShellTheme

LifecyclePopup {
    id: hardwarePopup
    property var barWindow
    property var hardwareSource
    anchor.window: barWindow
    anchor.rect.x: (barWindow.width - width) / 2
    anchor.rect.y: barWindow.height - barWindow.taskbarHeight - 3
    anchor.gravity: Edges.Top | Edges.Right
    implicitWidth: 620
    implicitHeight: 900
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
            anchors.margins: 14
            spacing: 6

            Row {
                width: parent.width
                height: 30

                Text {
                    width: parent.width - hardwareDetailsButton.width - 8
                    text: "󰍛  Hardware"
                    color: ShellTheme.color("#ffffff")
                    font.family: "Symbols Nerd Font"
                    font.pixelSize: 16
                    font.bold: true
                    anchors.verticalCenter: parent.verticalCenter
                }

                Rectangle {
                    id: hardwareDetailsButton
                    width: 92
                    height: 28
                    radius: 5
                    color: detailsMouse.containsMouse ? ShellTheme.color("#536d9b") : ShellTheme.color("#2b323b")
                    border.color: ShellTheme.color("#7188aa")
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                        anchors.centerIn: parent
                        text: "Details"
                        color: ShellTheme.color("#e8edf5")
                        font.pixelSize: 12
                        font.bold: true
                    }

                    MouseArea {
                        id: detailsMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            barWindow.openHardwareDetails()
                        }
                    }
                }
            }

            Rectangle { width: parent.width; height: 1; color: ShellTheme.color("#555555") }

            Text { text: "CPU"; color: ShellTheme.color("#8fb8ff"); font.pixelSize: 13; font.bold: true }
            Row {
                width: parent.width
                spacing: 12
                Column {
                    width: 250
                    spacing: 5
                    Text { text: "Load:  " + hardwareSource.cpuLoad + "\nCores:  " + hardwareSource.cpuCores; color: ShellTheme.color("#d8d8d8"); font.pixelSize: 14 }
                    Text { text: "Temperature:  " + hardwareSource.cpuTemperature + "\nPower:  " + hardwareSource.cpuPower; color: ShellTheme.color("#d8d8d8"); font.pixelSize: 14 }
                }
                TelemetryGraph { active: hardwarePopup.visible; width: 330; values: hardwareSource.cpuLoadHistory; strokeColor: ShellTheme.color("#8fb8ff"); fillColor: ShellTheme.color("#338fb8ff"); unit: "%" }
            }

            Text { text: "GPU"; color: ShellTheme.color("#8fb8ff"); font.pixelSize: 13; font.bold: true }
            Repeater {
                model: hardwareSource.gpuHistory
                delegate: Row {
                    required property int index
                    required property var modelData
                    width: parent.width
                    spacing: 12
                    Column {
                        width: 250
                        spacing: 5
                        Text { text: "GPU " + (index + 1) + ": " + modelData.name; color: ShellTheme.color("#d8d8d8"); font.pixelSize: 12; wrapMode: Text.Wrap; width: parent.width }
                        Text { text: "Load: " + modelData.loadText + "\nTemp: " + modelData.temperatureText; color: ShellTheme.color("#d8d8d8"); font.pixelSize: 12 }
                        Text { text: "VRAM: " + modelData.vramText + "\nPower: " + modelData.powerText; color: ShellTheme.color("#d8d8d8"); font.pixelSize: 12 }
                    }
                    TelemetryGraph { active: hardwarePopup.visible; width: 330; values: modelData.load; strokeColor: ShellTheme.color("#a8e6a3"); fillColor: ShellTheme.color("#33a8e6a3"); unit: "%" }
                }
            }
            Text { text: "Total GPU power: " + hardwareSource.gpuTotalPower; color: ShellTheme.color("#e8edf5"); font.pixelSize: 13; font.bold: true }

            Text { text: "RAM"; color: ShellTheme.color("#8fb8ff"); font.pixelSize: 13; font.bold: true }
            Row {
                width: parent.width
                spacing: 12
                Column {
                    width: 250
                    spacing: 5
                    Text { text: "Usage:  " + hardwareSource.memoryUsed + " / " + hardwareSource.memoryTotal + " (" + hardwareSource.memoryPercent + ")"; color: ShellTheme.color("#d8d8d8"); font.pixelSize: 14 }
                    Text { text: "Temperature:  " + hardwareSource.memoryTemperature; color: ShellTheme.color("#d8d8d8"); font.pixelSize: 14 }
                }
                TelemetryGraph { active: hardwarePopup.visible; width: 330; values: hardwareSource.memoryHistory; strokeColor: ShellTheme.color("#c6e48b"); fillColor: ShellTheme.color("#33c6e48b"); unit: "%" }
            }

            Text { text: "NVMe / M.2"; color: ShellTheme.color("#8fb8ff"); font.pixelSize: 13; font.bold: true }
            Text { text: "System (970 EVO Plus):  " + hardwareSource.systemStorageUsed + " / " + hardwareSource.systemStorageTotal + " (" + hardwareSource.systemStoragePercent + ")"; color: ShellTheme.color("#d8d8d8"); font.pixelSize: 14 }
            Text { text: "Games (980):  " + hardwareSource.gamesStorageUsed + " / " + hardwareSource.gamesStorageTotal + " (" + hardwareSource.gamesStoragePercent + ")"; color: ShellTheme.color("#d8d8d8"); font.pixelSize: 14 }
            Text { text: "Total:  " + hardwareSource.storageUsed + " / " + hardwareSource.storageTotal + " (" + hardwareSource.storagePercent + ")"; color: ShellTheme.color("#d8d8d8"); font.pixelSize: 14 }
            Text { text: "Temperature:  " + hardwareSource.storageTemperature + "    M.2 #2:  " + hardwareSource.nvmeTemperature2; color: ShellTheme.color("#d8d8d8"); font.pixelSize: 14 }

            Text { text: "HDD"; color: ShellTheme.color("#8fb8ff"); font.pixelSize: 13; font.bold: true }
            Text { text: "Unmounted (NTFS):  " + hardwareSource.hddCapacity + " capacity; usage unavailable"; color: ShellTheme.color("#d8d8d8"); font.pixelSize: 14 }

            Rectangle { width: parent.width; height: 1; color: ShellTheme.color("#555555") }
            Text { text: "Total Power Consumption: " + hardwareSource.totalPower; color: ShellTheme.color("#e8edf5"); font.pixelSize: 14; font.bold: true }
            Text { text: "Sum of available CPU and GPU power sensors."; color: ShellTheme.color("#aebdca"); font.pixelSize: 11; wrapMode: Text.Wrap; width: parent.width }
        }
    }
}
