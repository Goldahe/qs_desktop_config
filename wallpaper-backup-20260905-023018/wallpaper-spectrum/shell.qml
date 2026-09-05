import QtQuick
import Quickshell

ShellRoot {
    id: root

    property var spectrum: Array(44).fill(0.0)

    SpectrumReader {
        id: audioReader
        onSpectrumChanged: root.spectrum = spectrum
    }

    Variants {
        model: Quickshell.screens

        SpectrumSurface {
            required property var modelData
            outputScreen: modelData
            spectrum: root.spectrum
        }
    }
}
