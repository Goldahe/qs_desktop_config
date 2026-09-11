import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: hardwarePopup
    property var coordinator
    property bool stopping: false
    readonly property bool processActive: statsProcess.running
    property int samples: 0
    signal stopped()
    property string cpuLoad: "N/A"
    property string cpuCores: "N/A"
    property string cpuName: "N/A"
    property string cpuTemperature: "N/A"
    property string cpuPower: "N/A"
    property string totalPower: "N/A"
    property var processes: []
    property var ramProcesses: []
    property var storageDevices: []
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
    property int gpuCount: 0
    property string gpuTotalPower: "N/A"
    property var gpuProcesses: []
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

    // Use decimal SI display units throughout the hardware surfaces.
    function formatBytes(bytes) {
        const number = Number(bytes)
        if (!isFinite(number) || number < 0)
            return "N/A"
        const units = ["B", "KB", "MB", "GB", "TB"]
        let value = number
        let unit = 0
        while (value >= 1000 && unit < units.length - 1) {
            value /= 1000
            unit++
        }
        return value.toFixed(unit === 0 ? 0 : 1) + " " + units[unit]
    }

    function formatKiB(kibibytes) {
        return formatBytes(Number(kibibytes) * 1024)
    }

    function formatMemoryText(value) {
        const text = String(value).trim()
        const match = text.match(/^([0-9.]+)\s*(B|KiB|MiB|GiB|TiB|KB|MB|GB|TB)$/i)
        if (!match)
            return text === "" ? "N/A" : text
        const multiplier = {
            "b": 1, "kib": 1024, "mib": 1024 * 1024,
            "gib": 1024 * 1024 * 1024, "tib": 1024 * 1024 * 1024 * 1024,
            "kb": 1000, "mb": 1000 * 1000, "gb": 1000 * 1000 * 1000,
            "tb": 1000 * 1000 * 1000 * 1000
        }[match[2].toLowerCase()]
        return multiplier === undefined ? text : formatBytes(Number(match[1]) * multiplier)
    }

    function formatMemoryPair(used, total, percent) {
        const usedText = formatMemoryText(used)
        const totalText = formatMemoryText(total)
        if (usedText === "N/A" || totalText === "N/A")
            return "N/A"
        return usedText + " / " + totalText + (percent && percent !== "N/A" ? " (" + percent + ")" : "")
    }

    function formatStorage(bytes) {
        return formatBytes(bytes)
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
            if (fields.length < 10 || fields[0] !== "GPU")
                continue
            if (gpuText.length > 0)
                gpuText += "\n"
            gpuText += "GPU " + (Number(fields[1]) + 1) + ": " + shortGpuName(fields[3])
            gpuText += "\n  Load: " + fields[4] + "    Temperature: " + fields[5]
            gpuText += "\n  VRAM: " + formatMemoryPair(fields[6], fields[7], fields[8])
            gpuText += "    Power: " + fields[9]
        }
        gpuSummary = gpuText.length > 0 ? gpuText : "N/A"

        const cpuLoadMatch = output.match(/CPU_LOAD\s+([\d.]+)/)
        const cpuCoresMatch = output.match(/CPU_CORES\s+(\d+)/)
        const cpuNameMatch = output.match(/CPU_NAME\s+([^\n]+)/)
        const gpuCountMatch = output.match(/GPU_COUNT\s+(\d+)/)
        const cpuTempMatch = output.match(/CPU_TEMP\s+([^\s]+)/)
        const cpuPowerMatch = output.match(/CPU_POWER\s+([^\n]+)/)
        const totalPowerMatch = output.match(/TOTAL_POWER\s+([^\n]+)/)
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
        cpuName = cpuNameMatch ? cpuNameMatch[1].trim() : "N/A"
        gpuCount = gpuCountMatch ? Number(gpuCountMatch[1]) : 0
        let totalGpuPower = 0
        let hasGpuPower = false
        for (const line of gpuLines) {
            const fields = line.split("|")
            if (fields.length < 10 || fields[0] !== "GPU")
                continue
            const power = numeric(fields[9])
            if (!isNaN(power)) {
                totalGpuPower += power
                hasGpuPower = true
            }
        }
        gpuTotalPower = hasGpuPower ? totalGpuPower.toFixed(1) + " W" : "N/A"
        cpuTemperature = cpuTempMatch ? cpuTempMatch[1] : "N/A"
        cpuPower = cpuPowerMatch ? cpuPowerMatch[1].trim() : "N/A (RAPL restricted)"
        totalPower = totalPowerMatch ? totalPowerMatch[1].trim() : "N/A"
        cpuLoadHistory = appendHistory(cpuLoadHistory, cpuLoadMatch ? cpuLoadMatch[1] : NaN)

        const nextProcesses = []
        for (const line of gpuLines) {
            const fields = line.split("|")
            if (fields.length < 15 || fields[0] !== "PROC")
                continue
            nextProcesses.push({
                pid: fields[1], name: fields[2], cpu: fields[3], memory: fields[4],
                stat: fields[5], elapsed: fields[6], user: fields[7], rss: fields[8],
                vsz: fields[9], nice: fields[10], ni: fields[11], tty: fields[12],
                state: fields[13], command: fields.slice(14).join("|")
            })
        }
        processes = nextProcesses

        const nextRamProcesses = []
        for (const line of gpuLines) {
            const fields = line.split("|")
            if (fields.length < 11 || fields[0] !== "RAM_PROC")
                continue
            nextRamProcesses.push({
                pid: fields[1], name: fields[2], memory: fields[3], rss: fields[4],
                vsz: fields[5], cpu: fields[6], user: fields[7], stat: fields[8],
                elapsed: fields[9], command: fields.slice(10).join("|")
            })
        }
        ramProcesses = nextRamProcesses

        const nextStorageDevices = []
        for (const line of gpuLines) {
            const fields = line.split("|")
            if (fields.length < 11 || fields[0] !== "STORAGE")
                continue
            nextStorageDevices.push({
                index: Number(fields[1]), display: fields[2], name: fields[3], path: fields[4],
                type: fields[5], size: fields[6], transport: fields[7], medium: fields[8],
                mount: fields[9], filesystem: fields[10], processes: []
            })
        }
        for (const line of gpuLines) {
            const fields = line.split("|")
            if (fields.length < 10 || fields[0] !== "STORAGE_PROC")
                continue
            const device = nextStorageDevices.find(item => item.index === Number(fields[1]))
            if (device)
                device.processes.push({
                    pid: fields[2], name: fields[3], readBytes: fields[4], writeBytes: fields[5],
                    state: fields[6], command: fields.slice(7, fields.length - 2).join("|"),
                    readRate: fields[fields.length - 2], writeRate: fields[fields.length - 1]
                })
        }
        storageDevices = nextStorageDevices

        const nextGpuProcesses = []
        for (let i = 0; i < gpuCount; ++i)
            nextGpuProcesses.push([])
        for (const line of gpuLines) {
            const fields = line.split("|")
            if (fields.length < 14 || fields[0] !== "GPU_PROC")
                continue
            const gpuIndex = Number(fields[1])
            while (nextGpuProcesses.length <= gpuIndex)
                nextGpuProcesses.push([])
            nextGpuProcesses[gpuIndex].push({
                pid: fields[2], name: fields[3], gpuLoad: fields[4], cpu: fields[5], memory: fields[6],
                user: fields[7], rss: fields[8], vsz: fields[9], stat: fields[10],
                elapsed: fields[11], command: fields.slice(12, fields.length - 1).join("|"),
                gpuMemory: formatMemoryText(fields[fields.length - 1])
            })
            }
            for (const gpuList of nextGpuProcesses) {
            gpuList.sort(function(a, b) {
            const aLoad = numeric(a.gpuLoad)
            const bLoad = numeric(b.gpuLoad)
            if (isNaN(aLoad) && isNaN(bLoad)) return 0
            if (isNaN(aLoad)) return 1
            if (isNaN(bLoad)) return -1
            return bLoad - aLoad
            })
            }
            gpuProcesses = nextGpuProcesses
        gpuLoad = gpuLoadMatch ? gpuLoadMatch[1] + "%" : "N/A"
        gpuTemperature = gpuTempMatch ? gpuTempMatch[1] : "N/A"
        gpuJunction = gpuJunctionMatch ? gpuJunctionMatch[1] : "N/A"
        gpuMemoryTemperature = gpuMemoryTempMatch ? gpuMemoryTempMatch[1] : "N/A"
        gpuFan = gpuFanMatch ? gpuFanMatch[1] : "N/A"
        gpuPower = gpuPowerMatch ? gpuPowerMatch[1] : "N/A"

        if (gpuMemory) {
            gpuMemoryUsed = formatBytes(gpuMemory[1])
            gpuMemoryTotal = formatBytes(gpuMemory[2])
            gpuMemoryPercent = Number(gpuMemory[3]).toFixed(1) + "%"
        } else {
            gpuMemoryUsed = "N/A"
            gpuMemoryTotal = "N/A"
            gpuMemoryPercent = "N/A"
        }

        if (ram) {
            memoryUsed = formatBytes(ram[1])
            memoryTotal = formatBytes(ram[2])
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
            if (fields.length < 10 || fields[0] !== "GPU")
                continue
            const old = gpuHistory[Number(fields[1])] || {}
            const name = shortGpuName(fields[3])
            const load = appendHistory(old.load, numeric(fields[4]))
            const vramText = formatMemoryPair(fields[6], fields[7], fields[8])
            const unchanged = old.name === name
                              && old.loadText === fields[4]
                              && old.temperatureText === fields[5]
                              && old.vramText === vramText
                              && old.powerText === fields[9]
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
                    vramText: vramText,
                    powerText: fields[9]
                })
            }
        }
        if (nextGpuHistory.length !== gpuHistory.length)
            gpuHistoryChanged = true
        if (gpuHistoryChanged)
            gpuHistory = nextGpuHistory
    }

    function stop() {
        if (stopping)
            return
        stopping = true
        refreshTimer.stop()
        if (statsProcess.running) statsProcess.signal(15)
        else stopped()
    }
    function start() {
        stopping = false
        if (!statsProcess.running)
            statsProcess.running = true
        refreshTimer.start()
    }
    Process {
        id: statsProcess
        command: ["python", Qt.resolvedUrl("poll-session.py").toString().replace("file://", ""), Qt.resolvedUrl("hardware-stats.sh").toString().replace("file://", "")]
        running: true
        stdout: StdioCollector {
            onStreamFinished: if (!hardwarePopup.stopping) { hardwarePopup.updateStats(this.text); hardwarePopup.samples++ }
        }
        onExited: if (hardwarePopup.stopping) hardwarePopup.stopped()
    }
    Timer {
        id: refreshTimer
        interval: 1000
        running: !hardwarePopup.stopping
        repeat: true
        onTriggered: if (!statsProcess.running) statsProcess.running = true
    }
    Component.onDestruction: if (coordinator) coordinator.sessionDestroyed++
}
