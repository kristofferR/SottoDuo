import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Window {
    id: hud
    objectName: "dictationHud"
    transientParent: null
    required property var ui
    width: 360
    height: 74
    x: screen ? screen.virtualX + (screen.width - width) / 2 : 0
    y: screen ? screen.virtualY + screen.height - height - 72 : 0
    color: "transparent"
    flags: Qt.Tool | Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint | Qt.WindowDoesNotAcceptFocus | Qt.WindowTransparentForInput
    visible: bridge.connected && !bridge.preview && (!ui.visible || !ui.active) && (ui.busy || linger.running)
    property string phase: ui.activity.phase
    onPhaseChanged: {
        if (["completed", "failed", "cancelled"].includes(phase))
            linger.restart();
    }
    Timer {
        id: linger
        interval: 4500
    }
    Rectangle {
        anchors.fill: parent
        anchors.margins: 3
        radius: 22
        color: hud.ui.c.surface
        border.color: hud.ui.c.line
        RowLayout {
            anchors.centerIn: parent
            spacing: 14
            SLabel {
                ui: hud.ui
                text: hud.phase === "recording" ? "●" : "≋"
                color: hud.ui.c.accent
                font.pixelSize: 22
            }
            ColumnLayout {
                spacing: 3
                SLabel {
                    ui: hud.ui
                    text: hud.ui.messageFor(hud.phase)
                    font.weight: Font.DemiBold
                    font.pixelSize: 14
                }
                SLabel {
                    ui: hud.ui
                    text: hud.ui.activity.source || "Sotto"
                    color: hud.ui.c.muted
                    font.pixelSize: 11
                }
            }
        }
    }
}
