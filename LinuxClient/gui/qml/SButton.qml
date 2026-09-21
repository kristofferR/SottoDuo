import QtQuick
import QtQuick.Controls

Button {
    id: control
    required property var ui
    property bool primary: false
    font.pixelSize: 14
    padding: 12
    horizontalPadding: 18
    Accessible.name: text
    opacity: enabled ? 1 : 0.45
    contentItem: Text {
        text: control.text
        textFormat: Text.PlainText
        font: control.font
        color: control.primary ? control.ui.c.onAccent : control.ui.c.ink
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }
    background: Rectangle {
        radius: 9
        color: control.primary ? control.ui.c.accent : control.hovered ? control.ui.c.tint : control.ui.c.surface
        border.width: control.activeFocus ? 2 : 1
        border.color: control.activeFocus ? control.ui.c.accent : control.ui.c.line
    }
}
