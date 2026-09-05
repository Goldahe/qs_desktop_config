import QtQuick
import Quickshell
import Quickshell.Io

PopupWindow {
    id: hardwarePopup

    property var barWindow
    property string cpuLoad: "N/A"
    property string cpuCores: "N/A"
    property string cpuTemperature: "N/A"
    property string gpuLoad: "N/A"
    property string gpuTemperature: "N/A"
    property string gpuJunction: "N/A"
    property string gpuMemoryTemperature: "N/A"
    property string gpuFan: "N/A"
    property string gpuPower: "N/A"
    property string gpuMemoryUsed: "N/A"
    property string gpuMemoryTotal: "N/A"
    property string gpuMemoryPercent: "N/A"
    property string gpuSummary: "N/A"
    property var gpuHistory: []
    property var cpuLoadHistory: []
    property var memoryHistory: []
    property string memoryUsed: "N/A"
    property string memoryTotal: "N/A"
    property string memoryPercent: "N/A"
    readonly property string memoryTemperature: "N/A"
    property string storageUsed: "N/A"
    property string storageTotal: "N/A"
    property string storagePercent: "N/A"
    property string storageTemperature: "N/A"
    property string systemStorageUsed: "N/A"
    property string systemStorageTotal: "N/A"
    property string systemStoragePercent: "N/A"
    property string gamesStorageUsed: "N/A"
    property string gamesStorageTotal: "N/A"
    property string gamesStoragePercent: "N/A"
    property string nvmeTemperature2: "N/A"
    property string hddCapacity: "N/A"

    anchor.window: barWindow
    anchor.rect.x: (barWindow.width - width) / 2
    anchor.rect.y: barWindow.height - barWindow.taskbarHeight - 3
    anchor.gravity: Edges.Top | Edges.Right
    implicitWidth: 620
    implicitHeight: 760
    color: "transparent"
    visible: false
    grabFocus: true

    onVisibleChanged: {
        if (visible)
            statsProcess.running = true
        else if (statsProcess.running)
            statsProcess.running = false
    }

    function formatGiB(bytes) {
        return (Number(bytes) / (1024 * 1024 * 1024)).toFixed(1) + " GiB"
    }

    function formatStorage(bytes) {
        return (Number(bytes) / (1024 * 1024 * 1024)).toFixed(1) + " GiB"
    }

    function numeric(value) {
        const match = String(value).match(/[+-]?[0-9.]+/)
        return match ? Number(match[0]) : NaN
    }

    function appendHistory(history, value) {
        const next = history ? history.slice() : []
        const number = Number(value)
        if (!isNaN(number)) {
            if (next.length > 0 && next[next.length - 1] === number)
                return history
            next.push(number)
            if (next.length > 40)
                return next.slice(-40)
        }
        return next
    }

    function shortGpuName(name) {
        const text = String(name)
        if (text.indexOf("NVIDIA") >= 0 && text.indexOf("2080") >= 0)
            return "NVIDIA 2080 SUPER"
        if (text.indexOf("AMD") >= 0 && text.indexOf("Radeon") >= 0)
            return "AMD RX 7800 XT"
        return text.replace(/^.*controller: /, "").replace(/ \(rev .*\)$/, "")
    }

    function updateStats(output) {
        const gpuLines = output.split("\n")
        let gpuText = ""
        for (const line of gpuLines) {
            const fields = line.split("|")
            if (fields.length < 9 || fields[0] !== "GPU")
                continue
            if (gpuText.length > 0)
                gpuText += "\n"
            gpuText += "GPU " + (Number(fields[1]) + 1) + ": " + shortGpuName(fields[3])
            gpuText += "\n  Load: " + fields[4] + "    Temperature: " + fields[5]
            gpuText += "\n  VRAM: " + fields[6] + " / " + fields[7] + " (" + fields[8] + ")"
        }
        gpuSummary = gpuText.length > 0 ? gpuText : "N/A"

        const cpuLoadMatch = output.match(/CPU_LOAD\s+([\d.]+)/)
        const cpuCoresMatch = output.match(/CPU_CORES\s+(\d+)/)
        const cpuTempMatch = output.match(/CPU_TEMP\s+([^\s]+)/)
        const gpuLoadMatch = output.match(/GPU_LOAD\s+([^\s]+)/)
        const gpuTempMatch = output.match(/GPU_TEMP\s+([^\s]+)/)
        const gpuJunctionMatch = output.match(/GPU_JUNCTION\s+([^\s]+)/)
        const gpuMemoryTempMatch = output.match(/GPU_MEM_TEMP\s+([^\s]+)/)
        const gpuFanMatch = output.match(/GPU_FAN\s+([^\s]+)/)
        const gpuPowerMatch = output.match(/GPU_POWER\s+([^\s]+)/)
        const gpuMemory = output.match(/GPU_MEM\s+(\d+)\s+(\d+)\s+([\d.]+)/)
        const ram = output.match(/RAM\s+(\d+)\s+(\d+)\s+([\d.]+)/)
        const storage = output.match(/STORAGE\s+(\d+)\s+(\d+)\s+([\d.]+)/)
        const storageTempMatch = output.match(/STORAGE_TEMP\s+([^\s]+)/)
        const systemStorage = output.match(/NVME_SYSTEM\s+(\d+)\s+(\d+)\s+([\d.]+)/)
        const gamesStorage = output.match(/NVME_GAMES\s+(\d+)\s+(\d+)\s+([\d.]+)/)
        const nvmeTotal = output.match(/NVME_TOTAL\s+(\d+)\s+(\d+)\s+([\d.]+)/)
        const nvmeTemp2Match = output.match(/NVME_TEMP2\s+([^\s]+)/)
        const hddMatch = output.match(/HDD\s+(\d+)/)

        cpuLoad = cpuLoadMatch ? Number(cpuLoadMatch[1]).toFixed(1) + "%" : "N/A"
        cpuCores = cpuCoresMatch ? cpuCoresMatch[1] + " online" : "N/A"
        cpuTemperature = cpuTempMatch ? cpuTempMatch[1] : "N/A"
        cpuLoadHistory = appendHistory(cpuLoadHistory, cpuLoadMatch ? cpuLoadMatch[1] : NaN)
        gpuLoad = gpuLoadMatch ? gpuLoadMatch[1] + "%" : "N/A"
        gpuTemperature = gpuTempMatch ? gpuTempMatch[1] : "N/A"
        gpuJunction = gpuJunctionMatch ? gpuJunctionMatch[1] : "N/A"
        gpuMemoryTemperature = gpuMemoryTempMatch ? gpuMemoryTempMatch[1] : "N/A"
        gpuFan = gpuFanMatch ? gpuFanMatch[1] : "N/A"
        gpuPower = gpuPowerMatch ? gpuPowerMatch[1] : "N/A"

        if (gpuMemory) {
            gpuMemoryUsed = formatGiB(gpuMemory[1])
            gpuMemoryTotal = formatGiB(gpuMemory[2])
            gpuMemoryPercent = Number(gpuMemory[3]).toFixed(1) + "%"
        } else {
            gpuMemoryUsed = "N/A"
            gpuMemoryTotal = "N/A"
            gpuMemoryPercent = "N/A"
        }

        if (ram) {
            memoryUsed = formatGiB(ram[1])
            memoryTotal = formatGiB(ram[2])
            memoryPercent = Number(ram[3]).toFixed(1) + "%"
        } else {
            memoryUsed = "N/A"
            memoryTotal = "N/A"
            memoryPercent = "N/A"
        }
        memoryHistory = appendHistory(memoryHistory, ram ? ram[3] : NaN)

        if (storage) {
            storageUsed = formatStorage(storage[1])
            storageTotal = formatStorage(storage[2])
            storagePercent = Number(storage[3]).toFixed(1) + "%"
        } else {
            storageUsed = "N/A"
            storageTotal = "N/A"
            storagePercent = "N/A"
        }
        storageTemperature = storageTempMatch ? storageTempMatch[1] : "N/A"
        if (systemStorage) {
            systemStorageUsed = formatStorage(systemStorage[1])
            systemStorageTotal = formatStorage(systemStorage[2])
            systemStoragePercent = Number(systemStorage[3]).toFixed(1) + "%"
        } else {
            systemStorageUsed = "N/A"
            systemStorageTotal = "N/A"
            systemStoragePercent = "N/A"
        }
        if (gamesStorage) {
            gamesStorageUsed = formatStorage(gamesStorage[1])
            gamesStorageTotal = formatStorage(gamesStorage[2])
            gamesStoragePercent = Number(gamesStorage[3]).toFixed(1) + "%"
        } else {
            gamesStorageUsed = "N/A"
            gamesStorageTotal = "N/A"
            gamesStoragePercent = "N/A"
        }
        if (nvmeTotal) {
            storageUsed = formatStorage(nvmeTotal[1])
            storageTotal = formatStorage(nvmeTotal[2])
            storagePercent = Number(nvmeTotal[3]).toFixed(1) + "%"
        }
        nvmeTemperature2 = nvmeTemp2Match ? nvmeTemp2Match[1] : "N/A"
        hddCapacity = hddMatch ? formatStorage(hddMatch[1]) : "N/A"

        const nextGpuHistory = []
        let gpuHistoryChanged = false
        for (const line of gpuLines) {
            const fields = line.split("|")
            if (fields.length < 9 || fields[0] !== "GPU")
                continue
            const old = gpuHistory[Number(fields[1])] || {}
            const name = shortGpuName(fields[3])
            const load = appendHistory(old.load, numeric(fields[4]))
            const unchanged = old.name === name
                              && old.loadText === fields[4]
                              && old.temperatureText === fields[5]
                              && old.vramText === fields[8]
                              && load === old.load
            if (unchanged) {
                nextGpuHistory.push(old)
            } else {
                gpuHistoryChanged = true
                nextGpuHistory.push({
                    name: name,
                    load: load,
                    loadText: fields[4],
                    temperatureText: fields[5],
                    vramText: fields[8]
                })
            }
        }
        if (nextGpuHistory.length !== gpuHistory.length)
            gpuHistoryChanged = true
        if (gpuHistoryChanged)
            gpuHistory = nextGpuHistory
    }

    Process {
        id: statsProcess
        running: false
        command: ["/home/hawk/.config/quickshell/main/hardware-stats.sh"]
        stdout: StdioCollector {
            onStreamFinished: hardwarePopup.updateStats(this.text)
        }
    }

    Timer {
        interval: 3000
        running: hardwarePopup.visible
        repeat: true
        onTriggered: if (!statsProcess.running) statsProcess.running = true
    }

    Component.onCompleted: if (hardwarePopup.visible) statsProcess.running = true

    Rectangle {
        anchors.fill: parent
        radius: 8
        color: "#f0262626"
        border.color: "#555555"
        border.width: 1

        Column {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 6

            Text {
                text: "󰍛  Hardware"
                color: "white"
                font.family: "Symbols Nerd Font"
                font.pixelSize: 16
                font.bold: true
            }

            Rectangle { width: parent.width; height: 1; color: "#555555" }

            Text { text: "CPU"; color: "#8fb8ff"; font.pixelSize: 13; font.bold: true }
            Row {
                width: parent.width
                spacing: 12
                Column {
                    width: 250
                    spacing: 5
                    Text { text: "Load:  " + hardwarePopup.cpuLoad + "\nCores:  " + hardwarePopup.cpuCores; color: "#d8d8d8"; font.pixelSize: 14 }
                    Text { text: "Temperature:  " + hardwarePopup.cpuTemperature; color: "#d8d8d8"; font.pixelSize: 14 }
                }
                TelemetryGraph { active: hardwarePopup.visible; width: 330; values: hardwarePopup.cpuLoadHistory; strokeColor: "#8fb8ff"; fillColor: "#338fb8ff"; unit: "%" }
            }

            Text { text: "GPU"; color: "#8fb8ff"; font.pixelSize: 13; font.bold: true }
            Repeater {
                model: hardwarePopup.gpuHistory
                delegate: Row {
                    width: parent.width
                    spacing: 12
                    Column {
                        width: 250
                        spacing: 5
                        Text { text: "GPU " + (index + 1) + ": " + modelData.name; color: "#d8d8d8"; font.pixelSize: 12; wrapMode: Text.Wrap; width: parent.width }
                        Text { text: "Load: " + modelData.loadText + "\nTemp: " + modelData.temperatureText; color: "#d8d8d8"; font.pixelSize: 12 }
                        Text { text: "VRAM: " + modelData.vramText; color: "#d8d8d8"; font.pixelSize: 12 }
                    }
                    TelemetryGraph { active: hardwarePopup.visible; width: 330; values: modelData.load; strokeColor: "#a8e6a3"; fillColor: "#33a8e6a3"; unit: "%" }
                }
            }

            Text { text: "RAM"; color: "#8fb8ff"; font.pixelSize: 13; font.bold: true }
            Row {
                width: parent.width
                spacing: 12
                Column {
                    width: 250
                    spacing: 5
                    Text { text: "Usage:  " + hardwarePopup.memoryUsed + " / " + hardwarePopup.memoryTotal + " (" + hardwarePopup.memoryPercent + ")"; color: "#d8d8d8"; font.pixelSize: 14 }
                    Text { text: "Temperature:  " + hardwarePopup.memoryTemperature; color: "#d8d8d8"; font.pixelSize: 14 }
                }
                TelemetryGraph { active: hardwarePopup.visible; width: 330; values: hardwarePopup.memoryHistory; strokeColor: "#c6e48b"; fillColor: "#33c6e48b"; unit: "%" }
            }

            Text { text: "NVMe / M.2"; color: "#8fb8ff"; font.pixelSize: 13; font.bold: true }
            Text { text: "System (970 EVO Plus):  " + hardwarePopup.systemStorageUsed + " / " + hardwarePopup.systemStorageTotal + " (" + hardwarePopup.systemStoragePercent + ")"; color: "#d8d8d8"; font.pixelSize: 14 }
            Text { text: "Games (980):  " + hardwarePopup.gamesStorageUsed + " / " + hardwarePopup.gamesStorageTotal + " (" + hardwarePopup.gamesStoragePercent + ")"; color: "#d8d8d8"; font.pixelSize: 14 }
            Text { text: "Total:  " + hardwarePopup.storageUsed + " / " + hardwarePopup.storageTotal + " (" + hardwarePopup.storagePercent + ")"; color: "#d8d8d8"; font.pixelSize: 14 }
            Text { text: "Temperature:  " + hardwarePopup.storageTemperature + "    M.2 #2:  " + hardwarePopup.nvmeTemperature2; color: "#d8d8d8"; font.pixelSize: 14 }

            Text { text: "HDD"; color: "#8fb8ff"; font.pixelSize: 13; font.bold: true }
            Text { text: "Unmounted (NTFS):  " + hardwarePopup.hddCapacity + " capacity; usage unavailable"; color: "#d8d8d8"; font.pixelSize: 14 }
        }
    }
}
