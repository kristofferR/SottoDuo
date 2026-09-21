import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ColumnLayout {
    id: root
    required property var ui
    spacing: 24
    SLabel {
        ui: root.ui
        text: root.ui.busy ? "Current dictation" : "Ready when you are"
        color: root.ui.c.muted
        font.pixelSize: 13
    }
    SLabel {
        ui: root.ui
        text: root.ui.activity.phase === "completed" ? "Hold to dictate." : root.ui.messageFor(root.ui.activity.phase)
        font.pixelSize: 38
        font.weight: Font.DemiBold
        Layout.fillWidth: true
    }
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: route.implicitHeight + 28
        radius: 12
        color: root.ui.c.surface
        border.color: root.ui.c.line
        RowLayout {
            id: route
            anchors.fill: parent
            anchors.margins: 14
            spacing: 16
            SLabel {
                ui: root.ui
                text: root.ui.activity.source && root.ui.busy ? root.ui.activity.source : root.ui.sources.next ? root.ui.sources.next.name : "No available microphone"
                Layout.fillWidth: true
            }
            SLabel {
                ui: root.ui
                text: "→"
                color: root.ui.c.muted
            }
            SLabel {
                ui: root.ui
                text: root.ui.activity.trigger === "test" && root.ui.busy ? "Test in Sotto" : root.ui.snapshot.device ? root.ui.snapshot.device.name : "This computer"
            }
        }
    }
    RowLayout {
        Layout.fillWidth: true
        SLabel {
            ui: root.ui
            text: root.ui.connection
            color: root.ui.c.muted
            Layout.fillWidth: true
        }
        SButton {
            ui: root.ui
            text: "Check connection"
            onClicked: root.ui.refresh()
        }
    }
    RowLayout {
        SLabel {
            ui: root.ui
            text: "Last dictation"
            font.weight: Font.DemiBold
            Layout.fillWidth: true
        }
        SButton {
            ui: root.ui
            text: "Copy"
            enabled: !!root.ui.result && !root.ui.busy
            onClicked: {
                bridge.copy(root.ui.result.text);
                root.ui.notice = "Copied. Paste into your chosen field.";
            }
        }
    }
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 1
        color: root.ui.c.line
    }
    ScrollView {
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        TextArea {
            text: root.ui.result ? root.ui.result.text : root.ui.activity.phase === "recording" ? "Your microphone is recording. Text appears after transcription." : "Your next thought will appear here."
            readOnly: true
            selectByMouse: true
            wrapMode: TextEdit.Wrap
            textFormat: TextEdit.PlainText
            color: root.ui.result ? root.ui.c.ink : root.ui.c.muted
            font.pixelSize: 22
            background: null
            padding: 0
        }
    }
    SLabel {
        ui: root.ui
        Layout.fillWidth: true
        color: root.ui.c.muted
        font.pixelSize: 13
        text: root.ui.activity.phase === "failed" ? root.ui.snapshot.message : root.ui.result ? root.ui.result.delivery === "uncertain" ? "Insertion could not be confirmed. Check your field before copying to avoid a duplicate." : root.ui.result.delivery === "inserted" ? "Inserted at your cursor." : "Nothing was inserted. Your transcript is ready to copy." : "Use your configured desktop shortcut while your writing app is focused."
    }
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 1
        color: root.ui.c.line
    }
    RowLayout {
        Layout.fillWidth: true
        SButton {
            ui: root.ui
            primary: true
            text: root.ui.busy ? "Finish test" : "Test microphone"
            enabled: bridge.connected && root.ui.serverReady && (!root.ui.busy || (root.ui.activity.trigger === "test" && root.ui.activity.phase === "recording"))
            onClicked: bridge.request(root.ui.busy ? "stop" : "test")
        }
        SButton {
            ui: root.ui
            text: "Cancel"
            visible: root.ui.busy
            onClicked: bridge.request("cancel")
        }
        Item {
            Layout.fillWidth: true
        }
        SButton {
            ui: root.ui
            text: "History"
            onClicked: root.ui.page = 1
        }
    }
    SLabel {
        ui: root.ui
        text: "Microphone tests stay in Sotto and shared history. They are never inserted."
        font.pixelSize: 11
        color: root.ui.c.muted
        Layout.fillWidth: true
    }
}
