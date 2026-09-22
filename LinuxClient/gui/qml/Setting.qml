import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: row
    required property var ui
    property string title
    property string detail
    default property alias actions: actions.data
    Layout.fillWidth: true
    spacing: 0
    RowLayout {
        Layout.fillWidth: true
        Layout.margins: 14
        spacing: 20
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 6
            SLabel {
                ui: row.ui
                text: row.title
                Layout.fillWidth: true
            }
            SLabel {
                ui: row.ui
                text: row.detail
                visible: text.length > 0
                font.pixelSize: 13
                color: row.ui.c.muted
                Layout.fillWidth: true
            }
        }
        RowLayout {
            id: actions
            spacing: 8
        }
    }
    Rectangle {
        Layout.fillWidth: true
        Layout.leftMargin: 14
        Layout.rightMargin: 14
        Layout.preferredHeight: 1
        color: row.ui.c.line
        opacity: 0.65
    }
}
