.pragma library
var homeDir = "$HOME"
function expandHome(path) {
    var value = String(path || "")
    return value.indexOf("$HOME") === 0 ? homeDir + value.substring(5) : value
}
var wallpaperSource = homeDir + '/Downloads/frieren-beyond-journeys-end-5k-x6-2560x1440.jpg'
var perScreenWallpapers = ({'DP-1': '$HOME/Downloads/wp5576096-25601440-wallpapers.jpg', 'HDMI-A-1': '$HOME/Downloads/wp11018806-space-2560x1440-wallpapers.jpg'})
var barsEnabled = true
var wallpaperEnabled = true
var avatarEnabled = true
