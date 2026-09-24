import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

SButton {
    id: control
    primary: true
    Layout.preferredHeight: 52
    readonly property bool testing: ui.microphoneTestActive
    text: ui.microphoneTestStarting ? "Starting test…" : testing ? ui.activity.phase === "recording" ? "Finish test" : ui.activity.phase === "preparing" ? "Starting test…" : "Transcribing…" : "Test microphone"
    enabled: bridge.connected && !ui.shortcutBlocked && !ui.microphoneTestStarting && (ui.busy ? testing && ui.activity.phase === "recording" : ui.serverReady)
    ToolTip.visible: hovered
    ToolTip.text: "Test the saved microphone without inserting text."
    onClicked: ui.busy ? bridge.request("stop") : ui.startMicrophoneTest()
}
