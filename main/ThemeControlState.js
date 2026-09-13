.pragma library
var homeDir = "$HOME"
var selectedTheme = "custom"
function expandHome(path) {
    var value = String(path || "")
    return value === "$HOME" || value.indexOf("$HOME/") === 0 ? homeDir + value.substring(5) : value
}
var wallpaperSource = "$HOME/Pictures/Wallpapers/dark-souls-remastered-key-art-4k-p6-2560x1440.jpg"
var perScreenWallpapers = ({"DP-1":"$HOME/Pictures/Wallpapers/dark-souls-remastered-key-art-4k-p6-2560x1440.jpg","HDMI-A-1":"$HOME/Pictures/Wallpapers/dark-souls-girl-4k-b9-2560x1440.jpg"})
var barsEnabled = true
var wallpaperEnabled = true
var avatarEnabled = true
