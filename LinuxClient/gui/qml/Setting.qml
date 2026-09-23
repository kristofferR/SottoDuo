import QtQuick
import QtQuick.Layouts

RowLayout {
    id: row
    required property var ui
    property string title
    property string detail
    default property alias actions: actions.data
    Layout.fillWidth: true
    Layout.margins: 12
    spacing: 20
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 5
        SLabel {
            ui: row.ui
            text: row.title
            Layout.fillWidth: true
        }
        SLabel {
            ui: row.ui
            text: row.detail
            visible: text.length > 0
            font.pixelSize: 12
            color: row.ui.c.muted
            Layout.fillWidth: true
        }
    }
    RowLayout {
        id: actions
        spacing: 8
    }
}
