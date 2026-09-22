import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Sotto.Native 1.0

Window {
    id: hud
    objectName: "dictationHud"
    transientParent: null
    required property var ui
    width: 360
    height: 74
    // Wayland placement belongs to layer-shell; these are the X11 fallback.
    x: Qt.platform.pluginName.startsWith("wayland") ? 0 : (screen ? screen.virtualX + (screen.width - width) / 2 : 0)
    y: Qt.platform.pluginName.startsWith("wayland") ? 0 : (screen ? screen.virtualY + screen.height - height - 80 : 0)
    color: "transparent"
    flags: Qt.Tool | Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint | Qt.WindowDoesNotAcceptFocus | Qt.WindowTransparentForInput
    property bool surfaceReady: false
    Component.onCompleted: {
        HudSurface.configure(hud);
        surfaceReady = true;
    }
    visible: surfaceReady && bridge.connected && !bridge.preview && (!ui.visible || !ui.active) && (ui.busy || linger.running)
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
