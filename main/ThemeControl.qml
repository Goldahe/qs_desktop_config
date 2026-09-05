import QtQuick
import QtQuick.Dialogs
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
    property string pendingSource: "file://" + State.wallpaperSource
    property bool barsEnabled: State.barsEnabled
    property bool wallpaperEnabled: State.wallpaperEnabled
    property bool avatarEnabled: State.avatarEnabled
    property bool menuOpen: false

    function applyChanges() {
        Quickshell.execDetached(["python", root.controller, "--source", root.pendingSource,
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
            onClicked: root.menuOpen = !root.menuOpen
            cursorShape: Qt.PointingHandCursor
        }
    }

    FloatingWindow {
        id: menu
        title: "HK-47 Theme Control"
        implicitWidth: 360
        implicitHeight: 370
        visible: root.menuOpen
        color: "transparent"
        onVisibleChanged: root.menuOpen = visible

        Rectangle {
            anchors.fill: parent
            radius: 10
            color: "#f01a2028"
            border.color: "#668faabd"
            border.width: 1

            Column {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 9

                Row {
                    width: parent.width
                    height: 28
                    spacing: 8
                    Text { text: "HK-47  Theme Control"; color: "#bfeaff"; font.bold: true; font.pixelSize: 15 }
                    Item { width: parent.width - 190; height: 1 }
                    Text {
                        text: "×"
                        color: closeHover.containsMouse ? "#ffffff" : "#91a5b2"
                        font.pixelSize: 20
                        MouseArea { id: closeHover; anchors.fill: parent; hoverEnabled: true; onClicked: root.menuOpen = false }
                    }
                }

                Text { text: "Theme"; color: "#8da7b7"; font.pixelSize: 11 }
                Rectangle {
                    width: parent.width; height: 34; radius: 5
                    color: "#263843"
                    Text { anchors.left: parent.left; anchors.leftMargin: 10; anchors.verticalCenter: parent.verticalCenter; text: "Current theme: HK-47 Reactive"; color: "#e4f5ff" }
                }

                Text { text: "Artwork / supported file"; color: "#8da7b7"; font.pixelSize: 11 }
                Row {
                    width: parent.width; height: 132; spacing: 10
                    Rectangle {
                        width: 132; height: 132; radius: 5; color: "#10161b"; clip: true
                        Image { anchors.fill: parent; source: root.pendingSource; fillMode: Image.PreserveAspectCrop; asynchronous: true }
                        Text { anchors.centerIn: parent; text: "No preview"; color: "#78909c"; visible: preview.status !== Image.Ready }
                        Image { id: preview; anchors.fill: parent; source: root.pendingSource; fillMode: Image.PreserveAspectCrop; asynchronous: true; visible: false }
                    }
                    Column {
                        width: parent.width - 142; spacing: 8
                        Text { width: parent.width; text: root.pendingSource.replace("file://", ""); color: "#c9d7df"; elide: Text.ElideMiddle; wrapMode: Text.NoWrap }
                        Rectangle {
                            width: 150; height: 32; radius: 5; color: chooseHover.containsMouse ? "#36586b" : "#2c4654"
                            Text { anchors.centerIn: parent; text: "Choose artwork…"; color: "#e8f7ff" }
                            MouseArea { id: chooseHover; anchors.fill: parent; hoverEnabled: true; onClicked: picker.open(); cursorShape: Qt.PointingHandCursor }
                        }
                        Text { width: parent.width; text: "Images and video files are accepted."; color: "#80919a"; font.pixelSize: 11; wrapMode: Text.WordWrap }
                    }
                }

                Text { text: "Effects"; color: "#8da7b7"; font.pixelSize: 11 }
                CheckRow { label: "Spectrum bars"; checked: root.barsEnabled; onClicked: { root.barsEnabled = !root.barsEnabled; root.applyChanges() } }
                CheckRow { label: "Wallpaper reaction"; checked: root.wallpaperEnabled; onClicked: { root.wallpaperEnabled = !root.wallpaperEnabled; root.applyChanges() } }
                CheckRow { label: "HK-47 avatar popup"; checked: root.avatarEnabled; onClicked: { root.avatarEnabled = !root.avatarEnabled; root.applyChanges() } }

            }
        }
    }

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

    FileDialog {
        id: picker
        title: "Choose HK-47 artwork"
        fileMode: FileDialog.OpenFile
        nameFilters: ["Images and video (*.png *.jpg *.jpeg *.webp *.gif *.bmp *.mp4 *.mkv *.webm *.mov)", "All files (*)"]
        onAccepted: {
            root.pendingSource = selectedFile.toString()
            root.applyChanges()
        }
    }
}
