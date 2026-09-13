import QtQuick
import QtQuick.Controls
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "ThemeControlState.js" as State
import "ShellTheme.js" as ShellTheme

PanelWindow {
    id: root
    required property var outputScreen
    screen: outputScreen
    implicitWidth: 42
    implicitHeight: 42
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.namespace: "quickshell:hk47-theme-control"
    focusable: false
    exclusionMode: ExclusionMode.Ignore
    exclusiveZone: 0
    anchors { left: true; top: true }
    margins { left: 0; top: 0 }

    readonly property string controller: Qt.resolvedUrl("theme-control.py").toString().replace("file://", "")
    readonly property string homeDir: Quickshell.env("HOME") || ""
    property string pendingSource: "file://" + root.expandHome(State.wallpaperSource)
    property bool barsEnabled: State.barsEnabled
    property bool wallpaperEnabled: State.wallpaperEnabled
    property bool avatarEnabled: State.avatarEnabled
    property var availableThemes: []
    property string pendingTheme: State.selectedTheme
    property string themeLoadError: ""
    property bool operationInProgress: false
    property string operationStatus: ""
    property string operationError: ""
    property string operationOutput: ""
    property string operationKind: ""
    property var operationPayload: ({})
    readonly property bool menuOpen: menuSlot.item !== null
    property int previewsCreated: 0
    property int previewsDestroyed: 0
    // State.js is a pragma library, so accepted artwork needs an explicit
    // signal to make already-created preview delegates reevaluate.
    property int previewRevision: 0
    property var pickerItem: null
    property string pickerScreenName: ""
    readonly property bool pickerActive: pickerItem !== null
    property int pickersCreated: 0
    property int pickersDestroyed: 0

    function expandHome(path) {
        const value = String(path || "")
        return value === "$HOME" || value.indexOf("$HOME/") === 0 ? root.homeDir + value.substring(5) : value
    }

    // The coordinator can distinguish a native picker from its owning menu.
    // Closing the menu always closes both; closing just the picker keeps edits.
    function openPicker() {
        if (root.operationInProgress) return null
        if (pickerItem) return pickerItem
        pickerScreenName = ""
        return createPicker()
    }

    function openScreenPicker(screenName) {
        if (root.operationInProgress) return null
        if (pickerItem) return pickerItem
        pickerScreenName = screenName
        return createPicker()
    }

    function createPicker() {
        const owner = openMenu()
        if (!owner) return null
        pickerItem = pickerFactory.createObject(owner, {
            parentWindow: Qt.binding(function() { return owner.contentItem.Window.window })
        })
        const createdPicker = pickerItem
        Qt.callLater(function() {
            if (createdPicker && root.pickerItem === createdPicker)
                createdPicker.visible = true
        })
        return pickerItem
    }
    function closePicker(expected) {
        if (!pickerItem || (expected !== undefined && expected !== pickerItem)) return true
        const old = pickerItem
        pickerItem = null
        old.visible = false
        old.destroy()
        pickerScreenName = ""
        return true
    }
    function portableStatePath(source) {
        let value = String(source || "").replace(/^file:\/\//, "")
        return value === root.homeDir || value.indexOf(root.homeDir + "/") === 0 ? "$HOME" + value.substring(root.homeDir.length) : value
    }

    function acceptArtwork(source) {
        const selected = source.toString()
        const statePath = root.portableStatePath(selected)
        if (root.pickerScreenName !== "") {
            root.applyScreenWallpaper(root.pickerScreenName, selected, statePath)
        } else {
            root.applyGlobalWallpaper(selected, statePath)
        }
        root.pickerScreenName = ""
    }

    function openMenu() { return menuSlot.open() }
    function closeMenu() { return menuSlot.close() }
    function openThemeChoices() {
        const menu = openMenu()
        if (!menu) return
        Qt.callLater(function() {
            if (menu && menu.visible)
                menu.showThemeChoices()
        })
    }
    function lifecycleSnapshot() {
        return {
            menu: menuSlot.snapshot(),
            picker: {live: pickerActive, created: pickersCreated, destroyed: pickersDestroyed},
            previews: {created: previewsCreated, destroyed: previewsDestroyed,
                live: previewsCreated - previewsDestroyed}
        }
    }

    LifecycleSlot { id: menuSlot; name: "theme"; factory: menuFactory }

    Process {
        id: themeListProcess
        command: ["python", root.controller, "--list-json"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const parsed = JSON.parse(this.text)
                    root.availableThemes = Array.isArray(parsed) ? parsed : []
                    root.themeLoadError = root.availableThemes.length > 0 ? "" : "No valid themes found"
                } catch (error) {
                    root.availableThemes = []
                    root.themeLoadError = "Theme catalog unreadable"
                }
            }
        }
        stderr: StdioCollector {}
        onExited: function(exitCode) {
            if (exitCode !== 0)
                root.themeLoadError = "Theme catalog command failed"
        }
    }

    Process {
        id: themeApplyProcess
        running: false
        stdout: StdioCollector {
            onStreamFinished: root.operationOutput = this.text.trim()
        }
        stderr: StdioCollector {
            onStreamFinished: root.operationError = this.text.trim()
        }
        onExited: function(exitCode) {
            root.operationInProgress = false
            if (exitCode === 0) {
                root.operationStatus = "Theme operation complete"
                root.operationError = ""
                if (root.operationKind === "custom") {
                    State.selectedTheme = "custom"
                    State.barsEnabled = root.barsEnabled
                    State.wallpaperEnabled = root.wallpaperEnabled
                    State.avatarEnabled = root.avatarEnabled
                    if (root.operationPayload.type === "global") {
                        State.wallpaperSource = root.operationPayload.path
                        root.pendingSource = root.operationPayload.source
                        root.previewRevision++
                    } else if (root.operationPayload.type === "screen") {
                        State.perScreenWallpapers[root.operationPayload.screen] = root.operationPayload.path
                        root.previewRevision++
                    }
                    root.pendingTheme = "custom"
                } else if (root.operationKind === "theme") {
                    Quickshell.reload(true)
                }
            } else {
                root.operationStatus = ""
                root.barsEnabled = State.barsEnabled
                root.wallpaperEnabled = State.wallpaperEnabled
                root.avatarEnabled = State.avatarEnabled
                root.pendingSource = "file://" + root.expandHome(State.wallpaperSource)
                if (root.operationError === "")
                    root.operationError = "Theme operation failed (exit " + exitCode + ")"
            }
            root.operationKind = ""
            root.operationPayload = ({})
        }
    }

    function startOperation(arguments, kind, closeAfter, payload) {
        if (root.operationInProgress)
            return false
        root.operationInProgress = true
        root.operationStatus = "Applying…"
        root.operationError = ""
        root.operationOutput = ""
        root.operationKind = kind
        root.operationPayload = payload || ({})
        themeApplyProcess.command = ["python", root.controller].concat(arguments)
        themeApplyProcess.running = true
        if (closeAfter)
            root.closeMenu()
        return true
    }

    function themeIndex(themeId) {
        for (let index = 0; index < availableThemes.length; ++index) {
            if (availableThemes[index].id === themeId)
                return index
        }
        return -1
    }

    function applyTheme(themeId) {
        if (!themeId || themeIndex(themeId) < 0 || root.operationInProgress)
            return false
        return root.startOperation(["--theme", themeId, "--no-main-reload"], "theme", true)
    }

    function applyChanges() {
        root.startOperation(["--source", root.pendingSource,
            "--bars", root.barsEnabled ? "1" : "0",
            "--wallpaper", root.wallpaperEnabled ? "1" : "0",
            "--avatar", root.avatarEnabled ? "1" : "0"], "custom", false)
    }

    function applyGlobalWallpaper(sourceFile, statePath) {
        root.startOperation(["--source", sourceFile,
            "--bars", root.barsEnabled ? "1" : "0",
            "--wallpaper", root.wallpaperEnabled ? "1" : "0",
            "--avatar", root.avatarEnabled ? "1" : "0"], "custom", false,
            {type: "global", source: sourceFile, path: statePath})
    }

    function screenWallpaperSource(screenName) {
        // Read the revision so accepted artwork invalidates this binding even
        // though the source lives in a pragma-library JS object.
        const revision = root.previewRevision
        const source = State.perScreenWallpapers[screenName] || State.wallpaperSource
        const expanded = root.expandHome(source)
        return expanded.startsWith("file://") ? expanded : "file://" + expanded
    }

    function applyScreenWallpaper(screenName, sourceFile, statePath) {
        root.startOperation(["--screen", screenName,
            "--screen-wallpaper", sourceFile,
            "--bars", root.barsEnabled ? "1" : "0",
            "--wallpaper", root.wallpaperEnabled ? "1" : "0",
            "--avatar", root.avatarEnabled ? "1" : "0"], "custom", false,
            {type: "screen", screen: screenName, path: statePath})
    }

    function isLargestScreen() {
        if (!outputScreen)
            return false
        const area = outputScreen.width * outputScreen.height
        for (const candidate of Quickshell.screens) {
            if (candidate.width * candidate.height > area)
                return false
        }
        return true
    }

    visible: isLargestScreen()

    Rectangle {
        id: reveal
        anchors.left: parent.left
        anchors.top: parent.top
        width: 4
        height: 28
        radius: 2
        color: hover.containsMouse || root.menuOpen ? ShellTheme.color("#70bfe8ff") : "transparent"
        border.color: hover.containsMouse || root.menuOpen ? ShellTheme.color("#587fa8bb") : "transparent"
        border.width: 1

        MouseArea {
            id: hover
            anchors.fill: parent
            hoverEnabled: true
            onClicked: root.menuOpen ? root.closeMenu() : root.openMenu()
            cursorShape: Qt.PointingHandCursor
        }
    }

    Component {
        id: menuFactory
        FloatingWindow {
            id: menu
            required property var lifecycleOwner
            property bool lifecycleClosing: false
            function prepareClose() { root.closePicker(); return true }
            function showThemeChoices() { themeSelector.popup.open() }
            Component.onDestruction: lifecycleOwner.disposed()
            onClosed: if (!lifecycleClosing) root.closeMenu()
            title: "HK-47 Theme Control"
            implicitWidth: 430
            implicitHeight: menuContent.implicitHeight + 28
            visible: false
            color: "transparent"
            onVisibleChanged: if (!visible && !lifecycleClosing) root.closeMenu()

            Rectangle {
                anchors.fill: parent
                radius: 10
                color: ShellTheme.color("#f01a2028")
                border.color: ShellTheme.color("#668faabd")
                border.width: 1

                Column {
                    id: menuContent
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 9

                    Row {
                        width: parent.width
                        height: 28
                        Text { width: parent.width; text: "HK-47  Theme Control"; color: ShellTheme.color("#bfeaff"); font.bold: true; font.pixelSize: 15 }
                    }

                    Text { text: "Theme"; color: ShellTheme.color("#8da7b7"); font.pixelSize: 11 }
                    ComboBox {
                        id: themeSelector
                        width: parent.width
                        height: 34
                        model: root.availableThemes
                        textRole: "name"
                        currentIndex: Math.max(0, root.themeIndex(root.pendingTheme))
                        enabled: root.availableThemes.length > 0 && !root.operationInProgress
                        onActivated: function(index) {
                            if (index >= 0 && index < root.availableThemes.length)
                                root.pendingTheme = root.availableThemes[index].id
                        }
                        background: Rectangle {
                            radius: 5
                            color: themeSelector.hovered ? ShellTheme.color("#304c5b") : ShellTheme.color("#263843")
                            border.color: ShellTheme.color("#668faabd")
                            border.width: 1
                        }
                        contentItem: Text {
                            leftPadding: 10
                            rightPadding: themeSelector.indicator.width + 10
                            text: themeSelector.displayText
                            color: ShellTheme.color("#e4f5ff")
                            verticalAlignment: Text.AlignVCenter
                            elide: Text.ElideRight
                        }
                        delegate: ItemDelegate {
                            required property int index
                            required property var modelData
                            width: themeSelector.width
                            height: 30
                            highlighted: themeSelector.highlightedIndex === index
                            background: Rectangle {
                                color: parent.highlighted ? ShellTheme.color("#304c5b") : ShellTheme.color("#182a34")
                            }
                            contentItem: Text {
                                text: modelData.name
                                color: ShellTheme.color("#e4f5ff")
                                leftPadding: 8
                                verticalAlignment: Text.AlignVCenter
                                elide: Text.ElideRight
                            }
                        }
                        popup: Popup {
                            id: themePopup
                            y: themeSelector.height - 1
                            width: themeSelector.width
                            implicitHeight: Math.min(contentItem.implicitHeight + 2, 180)
                            padding: 1
                            modal: false
                            closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent
                            contentItem: ListView {
                                clip: true
                                implicitHeight: contentHeight
                                model: themePopup.visible ? themeSelector.delegateModel : null
                                currentIndex: themeSelector.highlightedIndex
                                ScrollIndicator.vertical: ScrollIndicator {}
                            }
                            background: Rectangle {
                                color: ShellTheme.color("#101820")
                                border.color: ShellTheme.color("#668faabd")
                                border.width: 1
                                radius: 5
                            }
                        }
                    }
                    Button {
                        id: applyThemeButton
                        width: parent.width
                        height: 30
                        text: "Apply theme"
                        enabled: !root.operationInProgress && root.themeIndex(root.pendingTheme) >= 0 && root.pendingTheme !== State.selectedTheme
                        onClicked: root.applyTheme(root.pendingTheme)
                        background: Rectangle {
                            radius: 5
                            color: applyThemeButton.enabled
                                ? (applyThemeButton.hovered ? ShellTheme.color("#3b88a3") : ShellTheme.color("#245a6d"))
                                : ShellTheme.color("#172a34")
                            border.color: applyThemeButton.enabled ? ShellTheme.color("#62b9d6") : ShellTheme.color("#31505e")
                            border.width: 1
                        }
                        contentItem: Text {
                            text: applyThemeButton.text
                            color: applyThemeButton.enabled ? ShellTheme.color("#d8f5ff") : ShellTheme.color("#607783")
                            font.bold: true
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                    Rectangle {
                        width: parent.width; height: 34; radius: 5
                        color: ShellTheme.color("#263843")
                        Text { anchors.left: parent.left; anchors.leftMargin: 10; anchors.verticalCenter: parent.verticalCenter; text: "Current theme: " + State.selectedTheme; color: ShellTheme.color("#e4f5ff") }
                    }
                    Text { visible: root.themeLoadError !== ""; text: root.themeLoadError; color: ShellTheme.color("#ffb4b4"); font.pixelSize: 11 }
                    Text { visible: root.operationStatus !== ""; text: root.operationStatus; color: ShellTheme.color("#9be9a8"); font.pixelSize: 11 }
                    Text { visible: root.operationError !== ""; text: root.operationError; color: ShellTheme.color("#ffb4b4"); font.pixelSize: 11; wrapMode: Text.Wrap; width: parent.width }

                    Text { text: "Per-display wallpapers"; color: ShellTheme.color("#8da7b7"); font.pixelSize: 11 }
                    Column {
                        width: parent.width
                        spacing: 5
                        Repeater {
                            model: Quickshell.screens
                            delegate: Rectangle {
                                required property var modelData
                                width: parent.width
                                height: 70
                                radius: 5
                                color: displayHover.containsMouse ? ShellTheme.color("#304c5b") : ShellTheme.color("#202f38")
                                border.color: ShellTheme.color("#496b7a")
                                border.width: 1

                                Rectangle {
                                    x: 8
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 86
                                    height: 54
                                    radius: 4
                                    color: ShellTheme.color("#10161b")
                                    clip: true
                                    Image {
                                        id: displayPreviewImage
                                        anchors.fill: parent
                                        source: root.screenWallpaperSource(modelData.name)
                                        fillMode: Image.PreserveAspectCrop
                                        asynchronous: true
                                        cache: false
                                        Component.onCompleted: root.previewsCreated++
                                        Component.onDestruction: root.previewsDestroyed++
                                    }
                                    Text {
                                        anchors.centerIn: parent
                                        text: "No preview"
                                        color: ShellTheme.color("#78909c")
                                        font.pixelSize: 10
                                        visible: displayPreviewImage.status !== Image.Ready
                                    }
                                }
                                Column {
                                    anchors.left: parent.left
                                    anchors.leftMargin: 104
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - 250
                                    Text {
                                        text: modelData.name || "Unnamed display"
                                        color: ShellTheme.color("#e4f5ff")
                                        font.bold: true
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        text: Math.round(modelData.width) + " × " + Math.round(modelData.height)
                                        color: ShellTheme.color("#8fa8b4")
                                        font.pixelSize: 10
                                    }
                                }
                                Rectangle {
                                    anchors.right: parent.right
                                    anchors.rightMargin: 8
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 125
                                    height: 28
                                    radius: 4
                                    color: chooseDisplayHover.containsMouse ? ShellTheme.color("#426b80") : ShellTheme.color("#315364")
                                    Text { anchors.centerIn: parent; text: "Choose wallpaper…"; color: ShellTheme.color("#e8f7ff"); font.pixelSize: 11 }
                                    MouseArea {
                                        id: chooseDisplayHover
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        onClicked: root.openScreenPicker(modelData.name)
                                        cursorShape: Qt.PointingHandCursor
                                    }
                                }
                                MouseArea {
                                    id: displayHover
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    z: -1
                                }
                            }
                        }
                    }

                    Text { text: "Effects"; color: ShellTheme.color("#8da7b7"); font.pixelSize: 11 }
                    CheckRow { label: "Spectrum bars"; enabled: !root.operationInProgress; checked: root.barsEnabled; onClicked: { root.barsEnabled = !root.barsEnabled; root.applyChanges() } }
                    CheckRow { label: "Wallpaper reaction"; enabled: !root.operationInProgress; checked: root.wallpaperEnabled; onClicked: { root.wallpaperEnabled = !root.wallpaperEnabled; root.applyChanges() } }
                    CheckRow { label: "HK-47 avatar popup"; enabled: !root.operationInProgress; checked: root.avatarEnabled; onClicked: { root.avatarEnabled = !root.avatarEnabled; root.applyChanges() } }

                }
            }
        }
    } // menuFactory

    component CheckRow: Rectangle {
        id: row
        property string label
        property bool checked
        signal clicked()
        width: parent.width
        height: 24
        color: "transparent"
        Rectangle { width: 16; height: 16; radius: 3; anchors.verticalCenter: parent.verticalCenter; color: row.checked ? ShellTheme.color("#61a9c8") : ShellTheme.color("#17242c"); border.color: ShellTheme.color("#6f9bab"); border.width: 1
            Text { anchors.centerIn: parent; text: "✓"; color: ShellTheme.color("#0b1720"); visible: row.checked; font.bold: true }
        }
        Text { anchors.left: parent.left; anchors.leftMargin: 25; anchors.verticalCenter: parent.verticalCenter; text: row.label; color: ShellTheme.color("#d6e3e8") }
        MouseArea { anchors.fill: parent; onClicked: row.clicked(); cursorShape: Qt.PointingHandCursor }
    }

    Component {
        id: pickerFactory
        FloatingWindow {
            id: picker
            property var parentWindow
            property url selectedFile: ""
            property string currentPath: ""
            implicitWidth: 560
            implicitHeight: 500
            visible: false
            color: "transparent"
            title: "HK-47 Wallpaper Selector"

            Component.onCompleted: {
                root.pickersCreated++
                folderModel.folder = "file://" + root.homeDir + "/Downloads"
            }
            Component.onDestruction: root.pickersDestroyed++
            onVisibleChanged: if (!visible && root.pickerItem === picker) root.closePicker(picker)

            FolderListModel {
                id: folderModel
                showFiles: true
                showDirs: true
                showDirsFirst: true
                showHidden: true
                nameFilters: ["*.png", "*.jpg", "*.jpeg", "*.webp", "*.gif", "*.bmp", "*.mp4", "*.mkv", "*.webm", "*.mov", "*.avi"]
                sortField: FolderListModel.Name
            }

            Rectangle {
                anchors.fill: parent
                radius: 10
                color: ShellTheme.color("#101820")
                border.width: 1
                border.color: ShellTheme.color("#62b9d6")
            }

            Column {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 9

                Row {
                    width: parent.width
                    height: 28
                    Text {
                        width: parent.width
                        text: "CHOOSE WALLPAPER  //  " + root.pickerScreenName
                        color: ShellTheme.color("#bcecff")
                        font.bold: true
                        font.pixelSize: 14
                        elide: Text.ElideRight
                        verticalAlignment: Text.AlignVCenter
                    }
                }

                Text {
                    width: parent.width
                    text: String(folderModel.folder).replace("file://", "")
                    color: ShellTheme.color("#87a8b8")
                    font.pixelSize: 11
                    elide: Text.ElideMiddle
                }

                Button {
                    width: parent.width
                    height: 30
                    text: "..  UP ONE DIRECTORY"
                    enabled: String(folderModel.folder) !== "file:///"
                    onClicked: folderModel.folder = folderModel.parentFolder
                    background: Rectangle {
                        radius: 5
                        color: parent.enabled ? (parent.down ? ShellTheme.color("#183e4c") : parent.hovered ? ShellTheme.color("#3b88a3") : ShellTheme.color("#245a6d")) : ShellTheme.color("#172a34")
                        border.width: 1
                        border.color: parent.enabled ? ShellTheme.color("#4e9bb5") : ShellTheme.color("#31505e")
                    }
                    contentItem: Text {
                        text: parent.text
                        color: parent.enabled ? ShellTheme.color("#d8f5ff") : ShellTheme.color("#607783")
                        font.pixelSize: 11
                        horizontalAlignment: Text.AlignLeft
                        verticalAlignment: Text.AlignVCenter
                        leftPadding: 10
                    }
                }

                ListView {
                    id: fileList
                    width: parent.width
                    height: parent.height - 28 - 30 - 30 - 18 - 30
                    clip: true
                    spacing: 4
                    model: folderModel
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                    delegate: Rectangle {
                        required property string fileName
                        required property url fileUrl
                        required property bool fileIsDir
                        width: fileList.width
                        height: 34
                        radius: 5
                        color: fileMouse.containsMouse || String(picker.selectedFile) === String(fileUrl) ? ShellTheme.color("#24485a") : ShellTheme.color("#182a34")
                        border.width: 1
                        border.color: fileMouse.containsMouse || String(picker.selectedFile) === String(fileUrl) ? ShellTheme.color("#62b9d6") : ShellTheme.color("#31505e")
                        Text {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            text: (fileIsDir ? "▸  " : "▣  ") + fileName
                            color: ShellTheme.color("#d8f5ff")
                            font.pixelSize: 12
                            verticalAlignment: Text.AlignVCenter
                            elide: Text.ElideRight
                        }
                        MouseArea {
                            id: fileMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: picker.selectedFile = fileIsDir ? "" : fileUrl
                            onDoubleClicked: if (fileIsDir) folderModel.folder = fileUrl
                        }
                    }
                }

                Row {
                    width: parent.width
                    height: 34
                    spacing: 8
                    Button {
                        width: (parent.width - parent.spacing) / 2
                        height: 34
                        text: "CHOOSE WALLPAPER"
                        enabled: !root.operationInProgress && String(picker.selectedFile) !== ""
                        onClicked: {
                            root.acceptArtwork(picker.selectedFile)
                            picker.visible = false
                        }
                        background: Rectangle {
                            radius: 5
                            color: parent.enabled ? (parent.down ? ShellTheme.color("#183e4c") : parent.hovered ? ShellTheme.color("#3b88a3") : ShellTheme.color("#245a6d")) : ShellTheme.color("#172a34")
                            border.width: 1
                            border.color: parent.enabled ? ShellTheme.color("#62b9d6") : ShellTheme.color("#31505e")
                        }
                        contentItem: Text {
                            text: parent.text
                            color: parent.enabled ? ShellTheme.color("#d8f5ff") : ShellTheme.color("#607783")
                            font.bold: true
                            font.pixelSize: 11
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                    Button {
                        width: (parent.width - parent.spacing) / 2
                        height: 34
                        text: "CANCEL"
                        onClicked: picker.visible = false
                        background: Rectangle {
                            radius: 5
                            color: parent.down ? ShellTheme.color("#183e4c") : parent.hovered ? ShellTheme.color("#24485a") : ShellTheme.color("#172a34")
                            border.width: 1
                            border.color: ShellTheme.color("#4e7788")
                        }
                        contentItem: Text {
                            text: parent.text
                            color: ShellTheme.color("#a9c4cf")
                            font.pixelSize: 11
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }
            }
        }
    }
}
