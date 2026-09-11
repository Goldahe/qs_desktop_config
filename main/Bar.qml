import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Pipewire

import Quickshell.Bluetooth

PanelWindow {
    id: bar

    anchors {
        bottom: true
        left: true
        right: true
    }

    property int taskbarHeight: 38
    property bool gameMode: false
    property bool modeTransitioning: false
    property bool pendingGameMode: false
    property bool overclocked: false
    property bool overclockTransitioning: false
    property bool pendingOverclock: false
    readonly property string modeSwitchPath: Qt.resolvedUrl("mode-switch.sh").toString().replace("file://", "")

    implicitHeight: taskbarHeight
    color: "#e6171717"
    exclusiveZone: implicitHeight

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }


    property var connectedBluetooth: {
        for (const device of Bluetooth.devices.values) {
            if (device.connected)
                return device
        }
        return null
    }

    // Explicit component interfaces for popup controls.
    property var powerMenu: powerSlot.item
    property var calendarMenu: calendarSlot.item
    property alias clockSource: clock
    property var hardwareMenu: hardwareSlot.item
    property var llmMenu: llmSlot.item
    property var chatterboxMenu: chatterboxSlot.item
    property var vfioMenu: vfioSlot.item

    Process {
        id: modeStateProcess
        command: ["sh", "-c", "grep -qx game \"$XDG_RUNTIME_DIR/quickshell-display-mode\""]
        running: true
        onExited: function(exitCode) {
            if (!bar.modeTransitioning)
                bar.gameMode = exitCode === 0
        }
    }

    Process {
        id: modeSwitchProcess
        command: ["bash", bar.modeSwitchPath, "work"]
        running: false
        onExited: function(exitCode) {
            bar.modeTransitioning = false
            if (exitCode !== 0)
                bar.gameMode = !bar.pendingGameMode
        }
    }

    Process {
        id: overclockStateProcess
        command: ["lact", "cli", "profile", "get"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                const profile = this.text.trim()
                if (!bar.overclockTransitioning)
                    bar.overclocked = profile === "OC_Games"
            }
        }
    }

    Process {
        id: overclockSwitchProcess
        command: ["lact", "cli", "profile", "set", "Default"]
        running: false
        stdout: StdioCollector {}
        stderr: StdioCollector {}
        onExited: function(exitCode) {
            bar.overclockTransitioning = false
            if (exitCode !== 0)
                bar.overclocked = !bar.pendingOverclock
        }
    }

    IpcHandler {
        target: "vfio"

        function toggle(): void {
            bar.togglePopup("vfio", false)
        }

        function show(): void {
            bar.openPopup("vfio", false)
        }

        function hide(): void {
            vfioSlot.close()
        }

        function diagnostics(): void {
            const popup = bar.openPopup("vfio", false)
            if (popup) popup.runDiagnostics()
        }
    }


    function bluetoothText() {
        if (!Bluetooth.defaultAdapter || !Bluetooth.defaultAdapter.enabled)
            return "󰂲"
        if (connectedBluetooth)
            return "󰂱  " + (connectedBluetooth.name || connectedBluetooth.deviceName)
        return "󰂯"
    }

    function powerAction(command) {
        Quickshell.execDetached(["sh", "-c", command])
        powerSlot.close()
    }

    function openCalendar() {
        powerSlot.close()
        togglePopup("calendar", true)
    }

    function chatterboxPopupX() {
        return centerControls.x + chatterboxControl.x +
               chatterboxControl.width / 2 - 240 / 2
    }

    function setGameMode(value) {
        if (modeTransitioning || gameMode === value)
            return
        pendingGameMode = value
        gameMode = value
        modeTransitioning = true
        modeSwitchProcess.command = ["bash", modeSwitchPath, value ? "game" : "work"]
        modeSwitchProcess.running = true
    }

    function setOverclocked(value) {
        if (overclockTransitioning || overclocked === value)
            return
        pendingOverclock = value
        overclocked = value
        overclockTransitioning = true
        overclockSwitchProcess.command = ["lact", "cli", "profile", "set", value ? "OC_Games" : "Default"]
        overclockSwitchProcess.running = true
    }

    IpcHandler {
        target: "displayMode"
        function toggle(): void { bar.setGameMode(!bar.gameMode) }
        function game(): void { bar.setGameMode(true) }
        function work(): void { bar.setGameMode(false) }
    }

    IpcHandler {
        target: "overclock"
        function toggle(): void { bar.setOverclocked(!bar.overclocked) }
        function defaultProfile(): void { bar.setOverclocked(false) }
        function games(): void { bar.setOverclocked(true) }
        function state(): string { return bar.overclocked ? "OC_Games" : "Default" }
    }

    Workspaces {}

    Row {
        id: centerControls
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        spacing: 4

        OverclockToggle {
            barWindow: bar
            overclocked: bar.overclocked
            busy: bar.overclockTransitioning
        }
        ModeToggle {
            barWindow: bar
        }
        HardwareButton {
            barWindow: bar
        }
        LlmButton {
            barWindow: bar
        }
        ChatterboxButton {
            id: chatterboxControl
            barWindow: bar
        }
    }

    StatusControls {
        barWindow: bar
        clock: clock
    }

    Variants {
        id: themeControls
        model: Quickshell.screens
        ThemeControl {
            required property var modelData
            outputScreen: modelData
        }
    }
    LifecycleSlot {
        id: powerSlot
        name: "power"
        factory: Component { PowerPopup { barWindow: bar } }
    }

    LifecycleSlot {
        id: calendarSlot
        name: "calendar"
        factory: Component { CalendarPopup { barWindow: bar; clock: bar.clockSource } }
    }
    property var popupOrder: []
    function slotFor(name) {
        return {power: powerSlot, calendar: calendarSlot, hardware: hardwareSlot,
                details: detailsSlot, llm: llmSlot, vfio: vfioSlot, wifi: wifiSlot, chatterbox: chatterboxSlot}[name] || null
    }
    function rememberPopup(name) {
        popupOrder = popupOrder.filter(n => n !== name).concat([name])
    }
    function themeController() {
        for (const controller of themeControls.instances)
            if (controller.visible) return controller
        return null
    }
    function openPopup(name, pointer) {
        if (name === "theme") { const controller = themeController(); return controller ? controller.openMenu() : null }
        const slot = slotFor(name)
        if (!slot) return null
        if (name === "hardware") { openHardware(pointer); return hardwareSlot.item }
        if (name === "details") { openHardwareDetails(); return detailsSlot.item }
        rememberPopup(name)
        const args = {grabFocus: !!pointer}
        if (name === "calendar") { args.year = clock.date.getFullYear(); args.month = clock.date.getMonth() }
        return slot.open(args)
    }
    function togglePopup(name, pointer) {
        const slot = slotFor(name)
        if (slot && slot.item && slot.snapshot().visible) slot.close()
        else openPopup(name, pointer)
    }
    function closeTopPopup() {
        // PopupWindows are not Hyprland active clients; never close the app underneath.
        for (let i = popupOrder.length - 1; i >= 0; --i) {
            const slot = slotFor(popupOrder[i])
            if (slot && slot.snapshot().visible) { slot.close(); return "closed" }
        }
        return "none"
    }
    IpcHandler {
        target: "lifecycle"
        function open(name: string): void { bar.openPopup(name, false) }
        function close(name: string): void {
            if (name === "theme") { const controller = bar.themeController(); if (controller) controller.closeMenu(); return }
            if (name === "hardware" || name === "details") bar.pendingHardware = null
            const slot = bar.slotFor(name); if (slot) slot.close()
        }
        function closeTop(): string { return bar.closeTopPopup() }
        function llmTab(index: int): void {
            const popup = bar.openPopup("llm", false)
            if (popup) popup.selectedTab = Math.max(0, Math.min(1, index))
        }
        function llmSection(index: int, expanded: bool): void {
            const popup = bar.openPopup("llm", false)
            if (popup) {
                popup.selectedTab = 1
                popup.setSectionExpanded(index, expanded)
            }
        }
        function llmOption(key: string, value: string, enabled: bool): void {
            const popup = bar.openPopup("llm", false)
            if (popup) {
                popup.selectedTab = 1
                popup.setCustomValue(key, value)
                popup.setCustomEnabled(key, enabled)
            }
        }
        function state(): string {
            const out = {}
            for (const name of ["calendar", "power", "hardware", "details", "llm", "vfio", "wifi", "chatterbox"])
                out[name] = bar.slotFor(name).snapshot()
            out.themeControllers = Array.from(themeControls.instances).map(c => ({visible: c.visible, screen: c.outputScreen ? c.outputScreen.name : "none"}))
            const theme = bar.themeController()
            if (theme) {
                const snapshot = theme.lifecycleSnapshot()
                out.theme = snapshot.menu
                out.themeResources = snapshot
            }
            if (calendarSlot.item) { out.calendar.year = calendarSlot.item.year; out.calendar.month = calendarSlot.item.month }
            if (detailsSlot.item) out.details.tab = detailsSlot.item.selectedTab
            if (llmSlot.item) {
                out.llm.tab = llmSlot.item.selectedTab
                out.llm.model = llmSlot.item.selectedModel
                out.llm.sections = llmSlot.item.customSections.length
                out.llm.inspected = !!llmSlot.item.modelInspection.model
                out.llm.inspectorActive = llmSlot.item.inspectorActive
                out.llm.estimateActive = llmSlot.item.estimateActive
                out.llm.estimate = llmSlot.item.resourceEstimate
                out.llm.estimateStatus = llmSlot.item.estimateStatus
                out.llm.serverRunning = llmSlot.item.serverRunning
            }
            out.session = {live: bar.hardwareSession !== null, created: bar.sessionCreated, destroyed: bar.sessionDestroyed,
                samples: bar.hardwareSession ? bar.hardwareSession.samples : 0,
                processActive: bar.hardwareSession ? bar.hardwareSession.processActive : false,
                cpu: bar.hardwareSession ? bar.hardwareSession.cpuLoad : "", gpuCount: bar.hardwareSession ? bar.hardwareSession.gpuCount : 0}
            return JSON.stringify(out)
        }
    }
    LifecycleSlot {
        id: wifiSlot
        name: "wifi"
        factory: Component { WifiPopup { barWindow: bar } }
    }
    property var hardwareSession: null
    property int sessionCreated: 0
    property int sessionDestroyed: 0
    property bool hardwareTransition: false
    property var pendingHardware: null
    Component {
        id: hardwareSessionFactory
        HardwareSession {
            coordinator: bar
            onStopped: bar.finishHardwareSession(this)
        }
    }
    function finishHardwareSession(session) {
        Qt.callLater(function() {
            const next = bar.pendingHardware
            bar.pendingHardware = null
            if (next) {
                if (next.view === "details") bar.openHardwareDetails()
                else bar.openHardware(next.pointer)
            }
        })
    }
    function ensureHardwareSession() {
        if (hardwareSession && hardwareSession.stopping) {
            if (hardwareSession.processActive)
                return false
            hardwareSession.start()
        }
        if (!hardwareSession) {
            hardwareSession = hardwareSessionFactory.createObject(bar)
            sessionCreated++
        }
        return hardwareSession !== null
    }
    function releaseHardwareSession() {
        if (!hardwareTransition && !hardwareSlot.snapshot().visible && !detailsSlot.snapshot().visible
                && hardwareSession && !hardwareSession.stopping)
            hardwareSession.stop()
    }
    function openHardware(pointer) {
        if (hardwareSession && hardwareSession.stopping && hardwareSession.processActive) { pendingHardware = {view: "hardware", pointer: pointer}; return }
        rememberPopup("hardware")
        if (ensureHardwareSession()) hardwareSlot.open({hardwareSource: hardwareSession, grabFocus: !!pointer})
    }
    function toggleHardware() {
        if (hardwareSlot.snapshot().visible || detailsSlot.snapshot().visible) { hardwareSlot.close(); detailsSlot.close() }
        else openHardware(true)
    }
    function openHardwareDetails() {
        if (hardwareSession && hardwareSession.stopping && hardwareSession.processActive) { pendingHardware = {view: "details"}; return }
        if (!ensureHardwareSession()) return
        hardwareTransition = true
        rememberPopup("details")
        const details = detailsSlot.open({hardwareSource: hardwareSession})
        if (details) hardwareSlot.close()
        hardwareTransition = false
    }
    LifecycleSlot {
        id: hardwareSlot
        name: "hardware"
        resident: true
        factory: Component { HardwarePopup { barWindow: bar } }
        onClosed: bar.releaseHardwareSession()
    }
    LifecycleSlot {
        id: detailsSlot
        name: "details"
        factory: Component { HardwareDetailsPopup { barWindow: bar } }
        onClosed: bar.releaseHardwareSession()
    }
    LifecycleSlot {
        id: llmSlot
        name: "llm"
        resident: true
        factory: Component { LlmPopup { barWindow: bar } }
    }
    LifecycleSlot {
        id: chatterboxSlot
        name: "chatterbox"
        factory: Component { ChatterboxPopup { barWindow: bar } }
    }
    LifecycleSlot {
        id: vfioSlot
        name: "vfio"
        factory: Component { VfioPopup { barWindow: bar } }
    }
}
