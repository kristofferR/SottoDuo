import QtQuick

Rectangle {
    required property bool ready
    implicitWidth: 6
    implicitHeight: 6
    radius: width / 2
    color: ready ? "#4ade80" : "#fb923c"
    Accessible.ignored: true
}
