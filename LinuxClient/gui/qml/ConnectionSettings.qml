import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Group {
    id: root
    objectName: "connectionSettings"
    title: "CONNECTION · THIS COMPUTER"
    property string ticket: ""
    property var hosts: []
    property string message: ""
    property bool pending: false
    property bool tested: false
    property bool dirty: false
    property string activeRequestID: ""
    function loadConnection() {
        server.text = ui.snapshot.server || "";
        deviceName.text = ui.snapshot.device ? ui.snapshot.device.name : "This computer";
    }
    Component.onCompleted: loadConnection()
    readonly property bool available: bridge.connected && !bridge.preview && !ui.snapshot.connectionChanging
    function edited() {
        ticket = "";
        tested = false;
        message = "";
        activeRequestID = "";
    }
    function clearSecret() {
        accessToken.clear();
    }
    Connections {
        target: root.ui
        function onVisibleChanged() {
            if (!root.ui.visible) {
                root.clearSecret();
                root.edited();
                root.pending = false;
            }
        }
    }
    Connections {
        target: bridge
        function onReply(action, data, requestID) {
            if (requestID !== root.activeRequestID || !root.pending)
                return;
            if (action === "testConnection") {
                root.pending = false;
                root.activeRequestID = "";
                if (!root.ui.visible)
                    return;
                root.ticket = data.ticket;
                root.hosts = data.hosts;
                hostPicker.currentIndex = root.hosts.indexOf(data.hostID);
                hostID.text = data.hostID || "";
                root.tested = true;
                root.message = data.message;
            } else if (action === "saveConnection") {
                root.pending = false;
                root.activeRequestID = "";
                root.ticket = "";
                root.tested = false;
                root.dirty = false;
                root.message = "Connection saved. To use the pairing button here, select this computer again below.";
                root.clearSecret();
                bridge.request("snapshot");
                root.ui.refresh();
            }
        }
        function onFailed(action, message, requestID) {
            if (requestID === root.activeRequestID && root.pending && ["testConnection", "saveConnection"].includes(action)) {
                root.pending = false;
                root.activeRequestID = "";
                root.ticket = "";
                root.message = message;
                root.clearSecret();
            }
        }
        function onSnapshotChanged() {
            if (bridge.connected && !root.dirty && !root.pending && !root.ticket)
                root.loadConnection();
            if (!bridge.connected) {
                root.pending = false;
                root.clearSecret();
                root.edited();
            }
        }
    }
    ColumnLayout {
        Layout.fillWidth: true
        Layout.margins: 12
        spacing: 10
        SLabel {
            ui: root.ui
            Layout.fillWidth: true
            text: "Connect this computer to your Sotto server. Shared transcription settings are in Server preferences."
            color: root.ui.c.muted
        }
        SLabel {
            ui: root.ui
            text: "Server address"
        }
        TextField {
            id: server
            objectName: "connectionServer"
            Layout.fillWidth: true
            placeholderText: "http://your-server:8391"
            Accessible.name: "Server address"
            enabled: root.available && !root.pending
            placeholderTextColor: root.ui.c.muted
            selectByMouse: true
            onTextEdited: {
                root.dirty = true;
                root.edited();
            }
        }
        SLabel {
            ui: root.ui
            text: "Access token"
        }
        TextField {
            id: accessToken
            objectName: "connectionToken"
            Layout.fillWidth: true
            placeholderText: root.ui.snapshot.setupRequired ? "Paste the server’s access token" : "Leave blank to keep the token for the same address"
            Accessible.name: "Access token"
            echoMode: TextInput.Password
            inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText
            maximumLength: 4096
            enabled: root.available && !root.pending
            placeholderTextColor: root.ui.c.muted
            selectByMouse: true
            onTextEdited: {
                root.dirty = true;
                root.edited();
            }
        }
        SLabel {
            ui: root.ui
            text: "Device name"
        }
        TextField {
            id: deviceName
            objectName: "connectionDeviceName"
            Layout.fillWidth: true
            Accessible.name: "Device name"
            maximumLength: 120
            enabled: root.available && !root.pending
            placeholderTextColor: root.ui.c.muted
            selectByMouse: true
            onTextEdited: {
                root.dirty = true;
                root.edited();
            }
        }
        SLabel {
            ui: root.ui
            visible: root.tested
            text: "Microphones provided by"
        }
        ComboBox {
            id: hostPicker
            objectName: "connectionHostPicker"
            Layout.fillWidth: true
            visible: root.tested && root.hosts.length > 0
            model: root.hosts
            enabled: !root.pending
            Accessible.name: "Microphone computer"
            displayText: currentIndex < 0 ? "Choose a computer" : currentText
        }
        TextField {
            id: hostID
            objectName: "connectionHostID"
            Layout.fillWidth: true
            visible: root.tested && root.hosts.length === 0
            placeholderText: "Capture host ID from the server setup"
            placeholderTextColor: root.ui.c.muted
            Accessible.name: "Capture host ID"
            maximumLength: 200
            enabled: !root.pending
        }
        SLabel {
            ui: root.ui
            Layout.fillWidth: true
            visible: root.tested && root.hosts.length === 0
            text: "The server has no microphone sources yet. Enter its capture host ID, or configure server audio and test again."
            color: root.ui.c.muted
        }
        SLabel {
            ui: root.ui
            Layout.fillWidth: true
            text: "Changing server or microphone computer resets your microphone choices. Saving ends pairing-button selection on this computer; it never starts recording."
            color: root.ui.c.muted
        }
        RowLayout {
            SButton {
                ui: root.ui
                objectName: "testConnectionButton"
                text: root.pending ? "Please wait…" : "Test connection"
                enabled: root.available && !root.pending && server.text.trim().length > 0 && deviceName.text.trim().length > 0
                onClicked: {
                    root.pending = true;
                    root.edited();
                    root.activeRequestID = String(Date.now()) + ":" + String(Math.random());
                    bridge.request("testConnection", {
                        server: server.text,
                        name: deviceName.text,
                        accessToken: accessToken.text
                    }, root.activeRequestID);
                    root.clearSecret();
                }
            }
            SButton {
                ui: root.ui
                objectName: "saveConnectionButton"
                text: "Save connection"
                enabled: root.available && !root.pending && !!root.ticket && !root.ui.busy && !root.ui.shortcutBlocked && (root.hosts.length ? hostPicker.currentIndex >= 0 : !!hostID.text.trim())
                onClicked: {
                    root.pending = true;
                    root.message = "";
                    root.activeRequestID = String(Date.now()) + ":" + String(Math.random());
                    bridge.request("saveConnection", {
                        ticket: root.ticket,
                        hostID: root.hosts.length ? hostPicker.currentText : hostID.text.trim()
                    }, root.activeRequestID);
                }
            }
        }
        SLabel {
            ui: root.ui
            objectName: "connectionSetupMessage"
            Layout.fillWidth: true
            visible: text.length > 0
            text: !bridge.connected ? "Start the installed background dictation service, then reconnect. In a terminal: systemctl --user start sotto-client.service" : root.message || root.ui.snapshot.setupMessage || ""
            Accessible.role: Accessible.AlertMessage
        }
        SButton {
            ui: root.ui
            visible: !bridge.connected
            text: "Reconnect"
            onClicked: bridge.request("snapshot")
        }
    }
}
