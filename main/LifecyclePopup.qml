import QtQuick
import Quickshell

PopupWindow {
    id: window
    property var lifecycleOwner
    property bool lifecycleClosing: false
    function prepareClose() { return true }
    Shortcut { sequence: "Escape"; enabled: visible; onActivated: lifecycleOwner.close() }
    Component.onDestruction: if (lifecycleOwner) lifecycleOwner.disposed()
}
