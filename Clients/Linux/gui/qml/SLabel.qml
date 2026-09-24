import QtQuick
import QtQuick.Controls

Label {
    required property var ui
    color: ui.c.ink
    font.pixelSize: 15
    wrapMode: Text.WordWrap
    textFormat: Text.PlainText
}
