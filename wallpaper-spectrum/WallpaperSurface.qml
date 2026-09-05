import QtQuick
import QtMultimedia
import Quickshell
import Quickshell.Wayland
import "Theme.js" as Theme
import HkSpectrum.Native 1.0 as Native

PanelWindow {
    id: surface
    required property var outputScreen
    required property var spectrumModel
    screen: outputScreen
    color: Theme.dimColor

    WlrLayershell.layer: WlrLayer.Background
    WlrLayershell.namespace: "quickshell:hk47-wallpaper"
    focusable: false
    exclusionMode: ExclusionMode.Ignore
    exclusiveZone: 0
    mask: Region {}
    anchors { left: true; right: true; top: true; bottom: true }

    readonly property string normalizedSource: Theme.wallpaperSource.startsWith("file://")
        ? Theme.wallpaperSource : "file://" + Theme.wallpaperSource
    readonly property string extension: {
        const value = Theme.wallpaperSource.toLowerCase().split("?")[0]
        const slash = value.lastIndexOf("/")
        const dot = value.lastIndexOf(".")
        return dot > slash ? value.slice(dot + 1) : ""
    }
    readonly property bool isVideo: {
        if (Theme.sourceType === "video") return true
        if (Theme.sourceType === "image") return false
        return ["mp4", "m4v", "mkv", "webm", "mov", "avi", "wmv", "ts", "m2ts"].indexOf(extension) >= 0
    }
    readonly property bool colorEffectActive: Theme.wallpaperColorEffectEnabled && !isVideo
    readonly property int selectedFillMode: {
        if (Theme.fitMode === "fit") return Image.PreserveAspectFit
        if (Theme.fitMode === "stretch") return Image.Stretch
        return Image.PreserveAspectCrop
    }

    Item {
        id: ordinaryContent
        anchors.fill: parent
        scale: Theme.mirror ? -1 : 1
        visible: !surface.colorEffectActive || !effectLoader.item || !effectLoader.item.ready

        Image {
            anchors.fill: parent
            visible: !surface.isVideo
            source: surface.normalizedSource
            fillMode: surface.selectedFillMode
            opacity: Theme.imageOpacity
            asynchronous: true
            cache: true
        }

        Loader {
            anchors.fill: parent
            active: surface.isVideo
            sourceComponent: videoWallpaper
        }
    }

    Loader {
        id: effectLoader
        anchors.fill: parent
        active: surface.colorEffectActive
        sourceComponent: Native.WallpaperSpectrum {
            model: surface.spectrumModel
            source: surface.normalizedSource
            fitMode: Theme.fitMode
            mirror: Theme.mirror
            imageOpacity: Theme.imageOpacity
            backgroundColor: Theme.dimColor
            dimOpacity: Theme.dimOpacity
            dimColor: Theme.dimColor
            hueOffset: Theme.hueOffset
            hueBinCount: Theme.wallpaperHueBinCount
        }
    }

    Rectangle {
        anchors.fill: parent
        visible: !surface.colorEffectActive
        color: Theme.dimColor
        opacity: Theme.dimOpacity
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
