.pragma library

var homeDir = "$HOME"
function expandHome(path) {
    var value = String(path || "")
    return value === "$HOME" || value.indexOf("$HOME/") === 0 ? homeDir + value.substring(5) : value
}

// Spectrum appearance and cadence.
var heightFraction = 0.5
var gain = 1.0
var opacity = 0.72
var hueOffset = 0.08
var frameRate = 24
var barsEnabled = true

// Integrated wallpaper source and ordinary rendering behavior.
var wallpaperSource = "$HOME/Pictures/Wallpapers/dark-souls-remastered-key-art-4k-p6-2560x1440.jpg"
var sourceType = "auto"
var fitMode = "crop"
var imageOpacity = 1.0
var dimOpacity = 0.0
var dimColor = "#080907"
var mirror = false
var loopVideo = true
var autoPlay = true
var playbackRate = 1.0

// Per-screen wallpaper overrides. Keys are screen names (e.g. "DP-1", "HDMI-A-1").
// Empty object means all screens use wallpaperSource above.
var perScreenWallpapers = ({"DP-1":"$HOME/Pictures/Wallpapers/dark-souls-remastered-key-art-4k-p6-2560x1440.jpg","HDMI-A-1":"$HOME/Pictures/Wallpapers/dark-souls-girl-4k-b9-2560x1440.jpg"})

// Exposed configuration toggle; a UI toggle may bind to this in the future.
// False destroys the full-screen shader item and uses the ordinary wallpaper path.
var wallpaperColorEffectEnabled = true
// Unique low-frequency bins used across the wallpaper's full mirrored hue cycle.
var wallpaperHueBinCount = 180
var wallpaperColorEffectIdleDelayMs = 15000
var wallpaperColorEffectFadeDurationMs = 2000
