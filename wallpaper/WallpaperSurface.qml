import QtQuick
import QtMultimedia
import Quickshell
import Quickshell.Wayland
import "Theme.js" as Theme

// One click-through background surface per physical monitor.
PanelWindow {
    id: surface

    required property var outputScreen
    screen: outputScreen
    color: Theme.dimColor

    WlrLayershell.layer: WlrLayer.Background
    WlrLayershell.namespace: "quickshell:hk47-wallpaper"
    focusable: false
    exclusionMode: ExclusionMode.Ignore
    exclusiveZone: 0
    mask: Region {}

    anchors {
        left: true
        right: true
        top: true
        bottom: true
    }

    readonly property string normalizedSource: {
        if (Theme.wallpaperSource.startsWith("file://"))
            return Theme.wallpaperSource
        return "file://" + Theme.wallpaperSource
    }

    readonly property string extension: {
        const value = Theme.wallpaperSource.toLowerCase().split("?")[0]
        const slash = value.lastIndexOf("/")
        const dot = value.lastIndexOf(".")
        return dot > slash ? value.slice(dot + 1) : ""
    }

    readonly property bool isVideo: {
        if (Theme.sourceType === "video")
            return true
        if (Theme.sourceType === "image")
            return false
        return ["mp4", "m4v", "mkv", "webm", "mov", "avi", "wmv", "ts", "m2ts"].indexOf(extension) >= 0
    }

    readonly property int selectedFillMode: {
        if (Theme.fitMode === "fit")
            return Image.PreserveAspectFit
        if (Theme.fitMode === "stretch")
            return Image.Stretch
        return Image.PreserveAspectCrop
    }

    Item {
        id: content
        anchors.fill: parent
        scale: Theme.mirror ? -1 : 1

        Image {
            id: still
            anchors.fill: parent
            visible: !surface.isVideo
            source: surface.normalizedSource
            fillMode: surface.selectedFillMode
            opacity: Theme.imageOpacity
            asynchronous: true
            cache: true
        }

        // Do not instantiate QtMultimedia for still images. A dormant
        // MediaPlayer probes hardware decoders and can open the reserved NVIDIA
        // GPU even when its source is empty.
        Loader {
            anchors.fill: parent
            active: surface.isVideo
            sourceComponent: videoWallpaper
        }

        Component {
            id: videoWallpaper

            Item {
                anchors.fill: parent

                MediaPlayer {
                    id: player
                    source: surface.normalizedSource
                    loops: Theme.loopVideo ? MediaPlayer.Infinite : 1
                    playbackRate: Theme.playbackRate
                    autoPlay: Theme.autoPlay
                    videoOutput: video
                }

                VideoOutput {
                    id: video
                    anchors.fill: parent
                    fillMode: surface.selectedFillMode
                    opacity: Theme.imageOpacity
                }
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.dimColor
        opacity: Theme.dimOpacity
    }
}
