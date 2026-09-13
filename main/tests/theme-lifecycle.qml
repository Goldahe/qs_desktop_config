import QtQuick
import Quickshell

ShellRoot {
    id: test
    property int applied: 0
    ThemeControl {
        id: theme
        outputScreen: null
        // Acceptance exercises resident routing without invoking live effects.
        function applyChanges() { test.applied++ }
        function applyGlobalWallpaper(sourceFile, statePath) {
            pendingSource = sourceFile
            State.wallpaperSource = statePath
            previewRevision++
            test.applied++
        }
    }
    property int step: 0
    property var dialog: null
    property var window: null
    function check(value, message) {
        if (!value) throw new Error(message)
    }
    function checkHeader(item, content) {
        if (item.text === "×") {
            const edge = item.mapToItem(content, item.width, item.height)
            check(edge.x <= content.width - 14, "close X remains inside header margins")
            check(edge.x >= content.width - 15, "close X is aligned to header right edge")
        }
        if (item.text === "HK-47 avatar popup") {
            const bottom = item.mapToItem(content, item.width, item.height)
            check(bottom.y <= content.height - 14, "last effect toggle remains inside menu")
        }
        for (const child of item.children) checkHeader(child, content)
    }
    function balanced() {
        const s = theme.lifecycleSnapshot()
        check(!theme.menuOpen && !s.menu.live, "menu is absent after close")
        check(s.menu.created === s.menu.destroyed, "menu destruction balanced")
        check(s.previews.created === s.previews.destroyed, "previews destruction balanced")
        check(!theme.pickerActive && !s.picker.live, "picker is absent")
        check(s.picker.created === s.picker.destroyed, "picker destruction balanced")
    }
    Timer {
        interval: 150; running: true; repeat: true
        onTriggered: {
            try {
                if (step === 0) {
                    check(typeof theme.openMenu === "function", "resident openMenu API missing")
                    check(!theme.menuOpen, "menu starts absent")
                    theme.pendingSource = ""
                    window = theme.openMenu()
                    check(theme.openMenu() === window, "open is idempotent")
                    check(theme.lifecycleSnapshot().menu.created === 1, "only one menu created")
                    check(theme.lifecycleSnapshot().previews.created === 1, "one decoded preview per menu")
                    theme.closeMenu()
                } else if (step === 1) {
                    check(theme.lifecycleSnapshot().picker !== undefined, "picker diagnostics missing")
                    balanced()
                    check(theme.pendingSource === "", "resident selection survives close")
                    window = theme.openMenu()
                    dialog = theme.openPicker()
                    check(dialog !== null && theme.pickerActive, "picker opened")
                    check(dialog === theme.openPicker(), "picker open idempotent")
                } else if (step === 2) {
                    checkHeader(window.contentItem, window.contentItem)
                    check(dialog.visible, "picker actually visible")
                    theme.closePicker(null)
                    check(theme.pickerActive, "stale destroyed picker callback cannot close current picker")
                    dialog.visible = false
                } else if (step === 3) {
                    check(!theme.pickerActive, "rejection disposes picker")
                    check(theme.menuOpen, "rejection keeps menu")
                    dialog = theme.openPicker()
                } else if (step === 4) {
                    dialog.visible = false
                } else if (step === 5) {
                    check(!theme.pickerActive, "plain close disposes picker")
                    dialog = theme.openPicker()
                } else if (step === 6) {
                    theme.closeMenu()
                } else if (step === 7) {
                    balanced()
                    window = theme.openMenu()
                    dialog = theme.openPicker()
                } else if (step === 8) {
                    dialog.selectedFile = Qt.resolvedUrl("test-artwork.svg")
                    theme.acceptArtwork(dialog.selectedFile)
                    dialog.visible = false
                } else if (step === 9) {
                    check(!theme.pickerActive, "acceptance disposes picker")
                    check(theme.pendingSource === Qt.resolvedUrl("test-artwork.svg").toString(), "accepted source resident")
                    check(test.applied === 1, "accepted result applies exactly once via resident root")
                    // Close the real backing QWindow, not an emitted mock signal.
                    window.contentItem.Window.window.close()
                } else if (step === 10) {
                    balanced()
                    window = theme.openMenu()
                    dialog = theme.openPicker()
                } else if (step === 11) {
                    window.contentItem.Window.window.close()
                } else if (step === 12) {
                    balanced()
                    window = theme.openMenu()
                } else if (step === 13) {
                    window.visible = false
                } else if (step === 14) {
                    balanced()
                    window = theme.openMenu()
                    dialog = theme.openPicker()
                    theme.closeMenu()
                } else {
                    balanced()
                    check(test.applied === 1, "dismissals never apply effects")
                    console.log("THEME_TEST_PASS " + JSON.stringify(theme.lifecycleSnapshot()))
                    Qt.quit()
                }
                step++
            } catch (e) { console.error("THEME_TEST_FAIL step=" + step + ": " + e); Qt.quit() }
        }
    }
}
