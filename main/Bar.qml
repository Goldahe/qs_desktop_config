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
    property var powerMenu: powerPopup
    property var calendarMenu: calendarPopup
    property var hardwareMenu: hardwarePopup
    property var chatterboxMenu: chatterboxPopup
    property var vfioMenu: vfioPopup

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

    IpcHandler {
        target: "vfio"

        function toggle(): void {
            vfioPopup.togglePopup()
        }

        function show(): void {
            vfioPopup.visible = true
            vfioPopup.refresh()
        }

        function hide(): void {
            vfioPopup.visible = false
        }

        function diagnostics(): void {
            vfioPopup.visible = true
            vfioPopup.runDiagnostics()
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
        powerPopup.visible = false
    }

    function openCalendar() {
        calendarPopup.year = clock.date.getFullYear()
        calendarPopup.month = clock.date.getMonth()
        powerPopup.visible = false
        calendarPopup.visible = !calendarPopup.visible
    }

    function chatterboxPopupX() {
        return centerControls.x + chatterboxControl.x +
               chatterboxControl.width / 2 - chatterboxPopup.width / 2
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

    IpcHandler {
        target: "displayMode"
        function toggle(): void { bar.setGameMode(!bar.gameMode) }
        function game(): void { bar.setGameMode(true) }
        function work(): void { bar.setGameMode(false) }
    }

    Workspaces {}

    Row {
        id: centerControls
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        spacing: 4

        ModeToggle {
            barWindow: bar
        }
        HardwareButton {
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
        model: Quickshell.screens
        ThemeControl {
            required property var modelData
            outputScreen: modelData
        }
    }
    PowerPopup {
        id: powerPopup
        barWindow: bar
    }

    CalendarPopup {
        id: calendarPopup
        barWindow: bar
        clock: clock
    }
    HardwarePopup {
        id: hardwarePopup
        barWindow: bar
    }
    ChatterboxPopup {
        id: chatterboxPopup
        barWindow: bar
    }
    VfioPopup {
        id: vfioPopup
        barWindow: bar
    }
}
