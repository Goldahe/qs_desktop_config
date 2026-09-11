import QtQuick
import Quickshell
import Quickshell.Io
ShellRoot {
    PanelWindow {
        id: testAnchor
        anchors.bottom: true
        implicitWidth: 1; implicitHeight: 1
        color: "transparent"
        exclusiveZone: 0
        property int taskbarHeight: 0
        property bool busyGap: false
        Timer {
            interval: 1; running: true; repeat: true
            onTriggered: if (slot.item && slot.item.actionMessage.indexOf("in progress") >= 0 && !slot.item.actionRunning) testAnchor.busyGap = true
        }
        LifecycleSlot {
            id: slot
            name: "guard"
            factory: Component { VfioPopup { barWindow: testAnchor } }
        }
        IpcHandler {
            target: "guard"
            function missing(): void {
                slot.open({grabFocus: false}).runAction("Missing command test", ["/nonexistent-qs-lifecycle-command"])
            }
            function fast(): void {
                const popup = slot.open({grabFocus: false})
                popup.runAction("Fast guard test", ["sleep", "0.05"])
            }
            function start(): void {
                const popup = slot.open({grabFocus: false})
                // The ONLY action in this test is an ordinary sleep process.
                popup.runAction("Lifecycle guard test", ["sleep", "1"])
            }
            function close(): bool { return slot.close() }
            function nativeHide(): void { if (slot.item) slot.item.visible = false }
            function state(): string {
                const out = slot.snapshot()
                out.visible = slot.item ? slot.item.visible : false
                out.busy = slot.item ? slot.item.actionRunning : false
                out.busyGap = testAnchor.busyGap
                return JSON.stringify(out)
            }
        }
    }
}
