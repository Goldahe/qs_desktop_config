pragma Singleton
import QtQuick

// Edit this file to change the wallpaper theme. Keep all theme decisions here.
QtObject {
    // Images: PNG, JPG/JPEG, WEBP, AVIF, GIF, BMP, SVG (backend permitting).
    // Video: MP4/MKV/WebM/MOV/M4V/AVI, including H.264/H.265 when QtMultimedia
    // has a decoder for the installed container and codec.
    property string wallpaperSource: "/games/Windows/VM-Share/ClipStudio_Project/HK-47.png"

    // "auto" selects Image or MediaPlayer from the file extension.
    // Override with "image" or "video" if a custom source needs it.
    property string sourceType: "auto"

    // "crop", "fit", or "stretch".
    property string fitMode: "crop"

    // Theme appearance knobs.
    property real imageOpacity: 1.0
    property real dimOpacity: 0.0
    property color dimColor: "#000000"
    property bool mirror: false

    // Video behavior.
    property bool loopVideo: true
    property bool autoplay: true
    property real playbackRate: 1.0
}
