import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: group
    required property var ui
    property string title
    default property alias rows: contents.data
    spacing: 12
    Layout.fillWidth: true
    SLabel {
        ui: group.ui
        text: group.title
        font.pixelSize: 16
        font.weight: Font.DemiBold
        color: group.ui.c.ink
        visible: text.length > 0
    }
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: contents.implicitHeight + 16
        color: group.ui.c.surface
        radius: 12
        border.color: group.ui.c.line
        ColumnLayout {
            id: contents
            anchors.fill: parent
            anchors.margins: 8
            spacing: 0
        }
    }
}
