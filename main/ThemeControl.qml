import QtQuick
import QtQuick.Controls
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Wayland
import "ThemeControlState.js" as State

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
        return value.indexOf("$HOME") === 0 ? root.homeDir + value.substring(5) : value
    }

    // The coordinator can distinguish a native picker from its owning menu.
    // Closing the menu always closes both; closing just the picker keeps edits.
    function openPicker() {
        if (pickerItem) return pickerItem
        pickerScreenName = ""
        return createPicker()
    }

    function openScreenPicker(screenName) {
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
        return value.indexOf(root.homeDir) === 0 ? "$HOME" + value.substring(root.homeDir.length) : value
    }

    function acceptArtwork(source) {
        const selected = source.toString()
        const statePath = root.portableStatePath(selected)
        if (root.pickerScreenName !== "") {
            State.perScreenWallpapers[root.pickerScreenName] = statePath
            root.applyScreenWallpaper(root.pickerScreenName, selected)
        } else {
            State.wallpaperSource = statePath
            root.pendingSource = selected
            root.applyChanges()
        }
        // Force existing Image bindings to reevaluate immediately. The helper
        // persists the same value to disk, while this keeps the open popup live.
        root.previewRevision++
        root.pickerScreenName = ""
    }

    function openMenu() { return menuSlot.open() }
    function closeMenu() { return menuSlot.close() }
    function lifecycleSnapshot() {
        return {
            menu: menuSlot.snapshot(),
            picker: {live: pickerActive, created: pickersCreated, destroyed: pickersDestroyed},
            previews: {created: previewsCreated, destroyed: previewsDestroyed,
                live: previewsCreated - previewsDestroyed}
        }
    }

    LifecycleSlot { id: menuSlot; name: "theme"; factory: menuFactory }

    function applyChanges() {
        Quickshell.execDetached(["python", root.controller, "--source", root.pendingSource,
            "--bars", root.barsEnabled ? "1" : "0",
            "--wallpaper", root.wallpaperEnabled ? "1" : "0",
            "--avatar", root.avatarEnabled ? "1" : "0"])
    }

    function screenWallpaperSource(screenName) {
        // Read the revision so accepted artwork invalidates this binding even
        // though the source lives in a pragma-library JS object.
        const revision = root.previewRevision
        const source = State.perScreenWallpapers[screenName] || State.wallpaperSource
        const expanded = root.expandHome(source)
        return expanded.startsWith("file://") ? expanded : "file://" + expanded
    }

    function applyScreenWallpaper(screenName, sourceFile) {
        Quickshell.execDetached(["python", root.controller, "--screen", screenName,
            "--screen-wallpaper", sourceFile,
            "--bars", root.barsEnabled ? "1" : "0",
            "--wallpaper", root.wallpaperEnabled ? "1" : "0",
            "--avatar", root.avatarEnabled ? "1" : "0"])
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
        color: hover.containsMouse || root.menuOpen ? "#70bfe8ff" : "transparent"
        border.color: hover.containsMouse || root.menuOpen ? "#587fa8bb" : "transparent"
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
                color: "#f01a2028"
                border.color: "#668faabd"
                border.width: 1

                Column {
                    id: menuContent
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 9

                    Row {
                        width: parent.width
                        height: 28
                        Text { width: parent.width; text: "HK-47  Theme Control"; color: "#bfeaff"; font.bold: true; font.pixelSize: 15 }
                    }

                    Text { text: "Theme"; color: "#8da7b7"; font.pixelSize: 11 }
                    Rectangle {
                        width: parent.width; height: 34; radius: 5
                        color: "#263843"
                        Text { anchors.left: parent.left; anchors.leftMargin: 10; anchors.verticalCenter: parent.verticalCenter; text: "Current theme: HK-47 Reactive"; color: "#e4f5ff" }
                    }

                    Text { text: "Per-display wallpapers"; color: "#8da7b7"; font.pixelSize: 11 }
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
                                color: displayHover.containsMouse ? "#304c5b" : "#202f38"
                                border.color: "#496b7a"
                                border.width: 1

                                Rectangle {
                                    x: 8
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 86
                                    height: 54
                                    radius: 4
                                    color: "#10161b"
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
                                        color: "#78909c"
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
                                        color: "#e4f5ff"
                                        font.bold: true
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        text: Math.round(modelData.width) + " × " + Math.round(modelData.height)
                                        color: "#8fa8b4"
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
                                    color: chooseDisplayHover.containsMouse ? "#426b80" : "#315364"
                                    Text { anchors.centerIn: parent; text: "Choose wallpaper…"; color: "#e8f7ff"; font.pixelSize: 11 }
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

                    Text { text: "Effects"; color: "#8da7b7"; font.pixelSize: 11 }
                    CheckRow { label: "Spectrum bars"; checked: root.barsEnabled; onClicked: { root.barsEnabled = !root.barsEnabled; root.applyChanges() } }
                    CheckRow { label: "Wallpaper reaction"; checked: root.wallpaperEnabled; onClicked: { root.wallpaperEnabled = !root.wallpaperEnabled; root.applyChanges() } }
                    CheckRow { label: "HK-47 avatar popup"; checked: root.avatarEnabled; onClicked: { root.avatarEnabled = !root.avatarEnabled; root.applyChanges() } }

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
        Rectangle { width: 16; height: 16; radius: 3; anchors.verticalCenter: parent.verticalCenter; color: row.checked ? "#61a9c8" : "#17242c"; border.color: "#6f9bab"; border.width: 1
            Text { anchors.centerIn: parent; text: "✓"; color: "#0b1720"; visible: row.checked; font.bold: true }
        }
        Text { anchors.left: parent.left; anchors.leftMargin: 25; anchors.verticalCenter: parent.verticalCenter; text: row.label; color: "#d6e3e8" }
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
                color: "#101820"
                border.width: 1
                border.color: "#62b9d6"
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
                        color: "#bcecff"
                        font.bold: true
                        font.pixelSize: 14
                        elide: Text.ElideRight
                        verticalAlignment: Text.AlignVCenter
                    }
                }

                Text {
                    width: parent.width
                    text: String(folderModel.folder).replace("file://", "")
                    color: "#87a8b8"
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
                        color: parent.enabled ? (parent.down ? "#183e4c" : parent.hovered ? "#3b88a3" : "#245a6d") : "#172a34"
                        border.width: 1
                        border.color: parent.enabled ? "#4e9bb5" : "#31505e"
                    }
                    contentItem: Text {
                        text: parent.text
                        color: parent.enabled ? "#d8f5ff" : "#607783"
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
                        color: fileMouse.containsMouse || String(picker.selectedFile) === String(fileUrl) ? "#24485a" : "#182a34"
                        border.width: 1
                        border.color: fileMouse.containsMouse || String(picker.selectedFile) === String(fileUrl) ? "#62b9d6" : "#31505e"
                        Text {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            text: (fileIsDir ? "▸  " : "▣  ") + fileName
                            color: "#d8f5ff"
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
                        enabled: String(picker.selectedFile) !== ""
                        onClicked: {
                            root.acceptArtwork(picker.selectedFile)
                            picker.visible = false
                        }
                        background: Rectangle {
                            radius: 5
                            color: parent.enabled ? (parent.down ? "#183e4c" : parent.hovered ? "#3b88a3" : "#245a6d") : "#172a34"
                            border.width: 1
                            border.color: parent.enabled ? "#62b9d6" : "#31505e"
                        }
                        contentItem: Text {
                            text: parent.text
                            color: parent.enabled ? "#d8f5ff" : "#607783"
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
                            color: parent.down ? "#183e4c" : parent.hovered ? "#24485a" : "#172a34"
                            border.width: 1
                            border.color: "#4e7788"
                        }
                        contentItem: Text {
                            text: parent.text
                            color: "#a9c4cf"
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
