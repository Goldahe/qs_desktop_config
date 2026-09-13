import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: portrait

    implicitWidth: 256
    implicitHeight: 256
    color: "transparent"
    property bool active: false

    function showAvatar() { active = true }
    function hideAvatar() { active = false }

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell:shrine-maiden-avatar"
    focusable: false
    exclusionMode: ExclusionMode.Ignore
    exclusiveZone: 0
    mask: Region {}

    anchors {
        left: true
        bottom: true
    }
    margins {
        left: Math.round((portrait.screen ? portrait.screen.width : 2560) / 2
                         - portrait.implicitWidth / 2)
        bottom: Math.round((portrait.screen ? portrait.screen.height : 1440) / 4
                           - portrait.implicitHeight / 2)
    }

    Image {
        anchors.fill: parent
        source: Qt.resolvedUrl("assets/fire-keeper.png")
        sourceSize.width: 256
        sourceSize.height: 256
        fillMode: Image.PreserveAspectFit
        smooth: true
        mipmap: false
        cache: true
        asynchronous: true
        opacity: portrait.active ? 1.0 : 0.0
        Behavior on opacity {
            NumberAnimation { duration: portrait.active ? 250 : 220 }
        }
    }
}
