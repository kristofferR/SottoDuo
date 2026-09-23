import QtQuick

Item {
    id: meter
    required property var ui
    property var levels: []
    implicitWidth: 64
    implicitHeight: 28
    Accessible.role: Accessible.Graphic
    Accessible.name: levels.length ? "Microphone input levels" : "Microphone levels unavailable"
    Row {
        anchors.fill: parent
        spacing: 3
        Repeater {
            model: 9
            Rectangle {
                required property int index
                readonly property real sample: meter.levels[index] || 0
                width: 4
                height: meter.levels.length ? 3 + 25 * Math.sqrt(Math.max(0, Math.min(1, sample))) : 2
                y: (meter.height - height) / 2
                radius: 2
                color: meter.levels.length ? meter.ui.c.accent : meter.ui.c.muted
                Accessible.ignored: true
            }
        }
    }
}
