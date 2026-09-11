import QtQuick

// Popup factory with an optional resident window tree.
QtObject {
    id: slot
    required property string name
    required property Component factory
    property bool resident: false
    property var item: null
    property int created: 0
    property int destroyed: 0
    property bool closing: false
    property var pendingOpen: null
    property Connections windowSignals: Connections {
        target: slot.item
        function onVisibleChanged() {
            if (slot.item && !slot.item.visible && !slot.closing) slot.close()
        }
        function onClosed() { if (slot.item && !slot.closing) slot.close() }
    }
    signal opened()
    signal closed()
    function open(properties) {
        if (closing) { pendingOpen = properties || {}; return null }
        if (item) {
            Object.assign(item, properties || {})
            item.visible = true
            opened()
            return item
        }
        const args = Object.assign({}, properties || {}, { lifecycleOwner: slot })
        item = factory.createObject(slot, args)
        if (!item) return null
        created++
        item.visible = true
        opened()
        return item
    }
    function close() {
        pendingOpen = null
        if (!item || closing) return true
        if (!item.prepareClose()) {
            // A native hide may arrive while an uncancellable VFIO action owns work.
            const blocked = item
            Qt.callLater(function() {
                if (slot.item === blocked && !blocked.visible) blocked.visible = true
            })
            return false
        }
        closing = true
        const old = item
        old.lifecycleClosing = true
        old.visible = false
        if (resident) {
            closing = false
            old.lifecycleClosing = false
            Qt.callLater(function() { slot.closed() })
            return true
        }
        item = null
        old.destroy()
        // Don't recreate in the same event turn before deferred deletion.
        Qt.callLater(function() {
            slot.closing = false
            slot.closed()
            if (slot.pendingOpen !== null) {
                const args = slot.pendingOpen
                slot.pendingOpen = null
                slot.open(args)
            }
        })
        return true
    }
    function disposed() { destroyed++ }
    function snapshot() {
        const pos = item ? item.contentItem.mapToGlobal(0, 0) : Qt.point(0, 0)
        return {live: item !== null, created: created, destroyed: destroyed, closing: closing,
                visible: item ? item.visible : false, x: pos.x, y: pos.y,
                width: item ? item.width : 0, height: item ? item.height : 0}
    }
}
