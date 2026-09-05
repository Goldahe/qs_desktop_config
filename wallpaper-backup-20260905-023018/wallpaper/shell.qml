import Quickshell

ShellRoot {
    // Quickshell.screens keeps the wallpaper duplicated correctly when monitors
    // are added, removed, or rearranged.
    Variants {
        model: Quickshell.screens

        WallpaperSurface {
            required property var modelData
            outputScreen: modelData
        }
    }
}
