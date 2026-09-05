.pragma library

// Spectrum appearance and cadence.
var heightFraction = 0.5
var gain = 1.0
var opacity = 0.85
var hueOffset = 0.0
var frameRate = 24

// Integrated wallpaper source and ordinary rendering behavior.
var wallpaperSource = "/home/hawk/Downloads/frieren-beyond-journeys-end-5k-x6-2560x1440.jpg"
var sourceType = "auto"       // auto, image, or video
var fitMode = "crop"          // crop, fit, or stretch
var imageOpacity = 1.0
var dimOpacity = 0.0
var dimColor = "#000000"
var mirror = false
var loopVideo = true
var autoPlay = true
var playbackRate = 1.0

// Exposed configuration toggle; a UI toggle may bind to this in the future.
// False destroys the full-screen shader item and uses the ordinary wallpaper path.
var wallpaperColorEffectEnabled = false
var wallpaperColorEffectIdleDelayMs = 15000
var wallpaperColorEffectFadeDurationMs = 2000
