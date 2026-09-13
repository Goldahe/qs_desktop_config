import QtQuick
import Quickshell
import Quickshell.Widgets
import "ShellTheme.js" as ShellTheme

Rectangle {
    id: overclockToggle
    property var barWindow
    property bool overclocked: false
    property bool busy: false

    width: 34
    height: 28
    radius: 5
    color: mouse.containsMouse
        ? (overclocked ? ShellTheme.color("#593536") : ShellTheme.color("#304f38"))
        : "transparent"
    opacity: busy ? 0.65 : 1.0

    IconImage {
        anchors.centerIn: parent
        width: 19
        height: 19
        source: Qt.resolvedUrl(overclocked
            ? "assets/overclock-gauge-red.svg"
            : "assets/overclock-gauge-green.svg")
        asynchronous: true
        mipmap: true
        backer.mirror: !overclocked
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: busy ? Qt.BusyCursor : Qt.PointingHandCursor
        onClicked: if (!busy) barWindow.setOverclocked(!overclocked)
    }

}
