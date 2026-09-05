import QtQuick
import Quickshell

PopupWindow {
    property var barWindow
    property var clock
    property int year: clock.date.getFullYear()
    property int month: clock.date.getMonth()
    readonly property int firstDay: new Date(year, month, 1).getDay()
    readonly property int daysInMonth: new Date(year, month + 1, 0).getDate()

    anchor.window: barWindow
    anchor.rect.x: barWindow.width - width - 72
    anchor.rect.y: barWindow.height - barWindow.taskbarHeight
    anchor.gravity: Edges.Top | Edges.Right
    implicitWidth: 286
    implicitHeight: 286
    color: "transparent"
    visible: false
    grabFocus: true

    function previousMonth() {
        if (month === 0) {
            month = 11
            year -= 1
        } else {
            month -= 1
        }
    }

    function nextMonth() {
        if (month === 11) {
            month = 0
            year += 1
        } else {
            month += 1
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: 8
        color: "#f0262626"
        border.color: "#555555"
        border.width: 1

        Column {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            Row {
                width: parent.width
                height: 28

                Text {
                    width: 32
                    height: parent.height
                    text: "‹"
                    color: "white"
                    font.pixelSize: 25
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    MouseArea {
                        anchors.fill: parent
                        onClicked: previousMonth()
                        cursorShape: Qt.PointingHandCursor
                    }
                }

                Text {
                    width: parent.width - 64
                    height: parent.height
                    text: Qt.formatDate(new Date(year, month, 1), "MMMM yyyy")
                    color: "white"
                    font.pixelSize: 15
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }

                Text {
                    width: 32
                    height: parent.height
                    text: "›"
                    color: "white"
                    font.pixelSize: 25
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    MouseArea {
                        anchors.fill: parent
                        onClicked: nextMonth()
                        cursorShape: Qt.PointingHandCursor
                    }
                }
            }

            Row {
                width: parent.width
                height: 22

                Repeater {
                    model: ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"]
                    delegate: Text {
                        required property string modelData
                        width: parent.width / 7
                        height: parent.height
                        text: modelData
                        color: "#858585"
                        font.pixelSize: 12
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                }
            }

            Grid {
                id: calendarGrid
                width: parent.width
                height: 180
                columns: 7
                rows: 6
                rowSpacing: 2
                columnSpacing: 2

                Repeater {
                    model: 42
                    delegate: Rectangle {
                        required property int index
                        readonly property int dayNumber: index - firstDay + 1
                        readonly property bool inMonth: dayNumber > 0 && dayNumber <= daysInMonth
                        readonly property bool isToday: inMonth
                            && year === clock.date.getFullYear()
                            && month === clock.date.getMonth()
                            && dayNumber === clock.date.getDate()
                        width: (calendarGrid.width - 12) / 7
                        height: (calendarGrid.height - 10) / 6
                        radius: 4
                        color: isToday ? "#536d9b" : "transparent"

                        Text {
                            anchors.fill: parent
                            text: parent.inMonth ? parent.dayNumber : ""
                            color: parent.isToday ? "white" : "#d0d0d0"
                            font.pixelSize: 13
                            font.bold: parent.isToday
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }
            }
        }
    }
}
