import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Group {
    id: root
    objectName: "djiSettings"
    title: "DJI receiver on server"
    property var receiver: null
    property bool checking: false
    property bool saving: false
    property bool choosing: false
    property bool showHelp: false
    property string error: ""
    property string receiverError: ""
    readonly property bool receiving: !!ui.snapshot.buttonEnabled
    readonly property var button: ui.snapshot.button || null
    readonly property bool selectedHere: !!button && !!button.selectedHere
    readonly property var destination: button ? button.selected : receiver ? receiver.selected : null
    readonly property bool available: button ? !!button.available : !!receiver && !!receiver.available
    function checkReceiver() {
        if (!bridge.connected || checking)
            return;
        checking = true;
        bridge.request("receiver");
    }
    Component.onCompleted: checkReceiver()
    Timer {
        interval: 5000
        running: bridge.connected && root.visible
        repeat: true
        onTriggered: root.checkReceiver()
    }
    Connections {
        target: bridge
        function onSnapshotChanged() {
            if (!bridge.connected) {
                root.receiver = null;
                root.checking = false;
                root.saving = false;
                root.choosing = false;
            }
        }
        function onReply(action, data) {
            if (action === "receiver") {
                root.receiver = data;
                root.receiverError = "";
                root.checking = false;
            }
            if (action === "saveButton") {
                root.saving = false;
                bridge.request("snapshot");
                root.checkReceiver();
            }
            if (action === "arm" || action === "disarm") {
                root.choosing = false;
                bridge.request("snapshot");
                root.checkReceiver();
            }
        }
        function onFailed(action, message) {
            if (["receiver", "saveButton", "arm", "disarm"].includes(action)) {
                if (action === "receiver") {
                    root.receiverError = message;
                    root.receiver = null;
                    root.checking = false;
                } else
                    root.error = message;
                if (action === "saveButton")
                    root.saving = false;
                if (action === "arm" || action === "disarm")
                    root.choosing = false;
            }
        }
    }
    Setting {
        ui: root.ui
        title: "Receive pairing-button dictation"
        detail: root.saving ? "Saving…" : !root.ui.snapshot.buttonSettingsSupported ? "Update the background client to change this setting." : "Allow this computer to receive commands from the server’s DJI receiver."
        Switch {
            objectName: "djiEnabledSwitch"
            Accessible.name: "Receive pairing-button dictation"
            checked: root.receiving
            enabled: bridge.connected && !!root.ui.snapshot.buttonSettingsSupported && !root.ui.busy && !root.saving && !root.choosing && !bridge.preview
            onClicked: {
                root.saving = true;
                root.error = "";
                bridge.request("saveButton", {
                    enabled: checked
                });
                checked = Qt.binding(() => root.receiving);
            }
        }
    }
    Setting {
        ui: root.ui
        title: "Receiver"
        detail: !bridge.connected ? "Connect to background dictation to check the receiver." : root.receiver ? root.receiver.source ? root.receiver.source.name : "No pairing-button receiver reported. Check its connection and setup on the server computer." : root.checking ? "Checking receiver…" : "Receiver has not been checked."
        SButton {
            ui: root.ui
            text: root.checking ? "Checking…" : "Check receiver"
            enabled: bridge.connected && !root.checking
            onClicked: root.checkReceiver()
        }
    }
    Setting {
        ui: root.ui
        visible: !!root.receiver && !!root.receiver.source
        title: "Transmitter link"
        detail: root.receiver && root.receiver.source ? root.receiver.source.link === "connected" ? "Connected. This does not confirm RF audio quality or mute state." : root.receiver.source.link === "disconnected" ? "Disconnected. Turn on the transmitter and link it to this receiver." : "Unknown. Wait for fresh receiver status or check device access on the server computer." : ""
    }
    Setting {
        ui: root.ui
        title: "Pairing button"
        detail: !bridge.connected ? "Unavailable while dictation is disconnected." : !root.receiver && !root.button ? "Availability not checked." : root.available ? "Receiver ready for pairing-button commands." : "Unavailable. Check the transmitter link and receiver access on the server computer."
    }
    SLabel {
        ui: root.ui
        Layout.fillWidth: true
        Layout.margins: 12
        font.pixelSize: 12
        color: root.ui.c.muted
        visible: !!root.receiver && !!root.receiver.source && !!root.receiver.source.reason && root.receiver.source.link !== "connected"
        text: root.receiver && root.receiver.source ? root.receiver.source.reason || "" : ""
    }
    Setting {
        ui: root.ui
        title: "Destination"
        detail: root.destination ? root.destination.device.name : "No destination selected"
        SButton {
            objectName: "djiSelectButton"
            ui: root.ui
            text: root.selectedHere ? "This computer selected" : "Use this computer"
            enabled: bridge.connected && root.receiving && !!root.button && root.available && !root.selectedHere && !root.ui.busy && !root.saving && !root.choosing && !bridge.preview
            onClicked: {
                root.choosing = true;
                root.error = "";
                bridge.request("arm");
            }
        }
        SButton {
            objectName: "djiDeselectButton"
            ui: root.ui
            text: "Deselect"
            enabled: bridge.connected && root.receiving && root.selectedHere && !root.ui.busy && !root.saving && !root.choosing && !bridge.preview
            onClicked: {
                root.choosing = true;
                root.error = "";
                bridge.request("disarm");
            }
        }
    }
    SLabel {
        ui: root.ui
        Layout.fillWidth: true
        Layout.margins: 12
        font.pixelSize: 12
        color: root.ui.c.muted
        text: "Select this computer, focus your text field, then tap the transmitter’s pairing button to start and again to stop. A successful keyboard dictation also selects this computer when receiving is enabled. Locking or disconnecting clears selection."
    }
    SLabel {
        ui: root.ui
        Layout.fillWidth: true
        Layout.margins: 12
        font.pixelSize: 12
        color: root.ui.c.muted
        text: "Keyboard dictation keeps microphone fallback. Pairing-button dictation uses only the server’s DJI receiver. Enabling receiving does not select a destination or start recording."
    }
    Setting {
        ui: root.ui
        title: "Receiver setup"
        SButton {
            ui: root.ui
            text: root.showHelp ? "Hide help" : "Setup help"
            onClicked: root.showHelp = !root.showHelp
        }
    }
    SLabel {
        ui: root.ui
        Layout.fillWidth: true
        Layout.margins: 12
        visible: root.showHelp
        font.pixelSize: 12
        text: "On the computer running the server: connect the USB receiver, turn on the transmitter, and check that they are linked.\n\nOn Linux, Sotto needs the DJI-only receiver and pairing-button access rules, and an active local login. If capture works but the pairing button is unavailable, check the pairing-button interface permission and server setup.\n\nCheck receiver reads status only. It does not record, reset the receiver, change Bluetooth connections, or select a destination."
    }
    SLabel {
        ui: root.ui
        objectName: "djiSettingsError"
        Layout.fillWidth: true
        Layout.margins: 12
        visible: text.length > 0
        text: root.error || root.receiverError
        Accessible.role: Accessible.AlertMessage
    }
}
