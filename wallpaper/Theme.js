// Theme configuration. Edit these values, then reload the wallpaper profile.
.pragma library

var homeDir = "$HOME"
function expandHome(path) {
    var value = String(path || "")
    return value.indexOf("$HOME") === 0 ? homeDir + value.substring(5) : value
}
var wallpaperSource = homeDir + '/Downloads/frieren-beyond-journeys-end-5k-x6-2560x1440.jpg'
var sourceType = "auto"       // auto, image, or video
var fitMode = "crop"           // crop, fit, or stretch
var imageOpacity = 1.0
var dimOpacity = 0.0
var dimColor = "#000000"
var mirror = false
var loopVideo = true
var autoPlay = true
var playbackRate = 1.0

// Per-screen wallpaper overrides. Keys are screen names (e.g. "DP-1", "HDMI-A-1").
// Empty object means all screens use wallpaperSource above.
// Example: { "DP-1": "/path/to/wallpaper1.jpg", "HDMI-A-1": "/path/to/wallpaper2.jpg" }
var perScreenWallpapers = ({'DP-1': '$HOME/Downloads/wp5576096-25601440-wallpapers.jpg', 'HDMI-A-1': '$HOME/Downloads/wp11018806-space-2560x1440-wallpapers.jpg'})
