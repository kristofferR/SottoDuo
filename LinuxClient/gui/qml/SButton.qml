import QtQuick
import QtQuick.Controls

Button {
    id: control
    required property var ui
    property bool primary: false
    property string symbolName: ""
    property string accessibleLabel: ""
    font.pixelSize: 15
    padding: 13
    horizontalPadding: 18
    Accessible.name: accessibleLabel || text
    opacity: enabled ? 1 : 0.45
    contentItem: Item {
        implicitWidth: contentRow.implicitWidth
        implicitHeight: Math.max(contentRow.implicitHeight, 18)
        Row {
            id: contentRow
            anchors.centerIn: parent
            spacing: control.symbolName && control.text ? 8 : 0
            Image {
                objectName: control.symbolName ? "buttonSymbol" : ""
                visible: control.symbolName.length > 0
                width: visible ? 17 : 0
                height: visible ? 17 : 0
                sourceSize: Qt.size(width * Screen.devicePixelRatio, height * Screen.devicePixelRatio)
                Accessible.ignored: true
                source: control.symbolName ? "data:image/svg+xml," + encodeURIComponent('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="' + (control.primary ? control.ui.c.onAccent : control.ui.c.accent) + '" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">' + ({
                    "copy": '<rect x="8" y="7" width="12" height="14" rx="2"/><path d="M16 7V5a2 2 0 0 0-2-2H6a2 2 0 0 0-2 2v12a2 2 0 0 0 2 2h2"/>',
                    "refresh": '<path d="M20 11a8 8 0 1 1-2.3-5.7"/><path d="M20 4v7h-7"/>',
                    "check": '<path d="m4 12 5 5L20 6"/>'
                })[control.symbolName] + '</svg>') : ""
            }
            Text {
                visible: control.text.length > 0
                text: control.text
                textFormat: Text.PlainText
                font: control.font
                color: control.primary ? control.ui.c.onAccent : control.ui.c.ink
                verticalAlignment: Text.AlignVCenter
            }
        }
    }
    background: Rectangle {
        radius: 9
        color: control.primary ? control.ui.c.accent : control.hovered ? control.ui.c.tint : control.ui.c.surface
        border.width: control.activeFocus ? 2 : 1
        border.color: control.activeFocus ? control.ui.c.accent : control.ui.c.line
    }
}
