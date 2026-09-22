import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ApplicationWindow {
    id: app
    width: 1040
    height: 740
    minimumWidth: 880
    minimumHeight: 620
    onClosing: close => {
        if (microphoneTestActive) {
            close.accepted = false;
            page = 0;
            notice = "Finish or cancel the microphone test before closing Sotto.";
        }
    }
    onVisibleChanged: {
        if (!visible)
            finishShortcutCheck();
    }
    property bool startHidden: false
    visible: !startHidden
    title: bridge.preview ? "Sotto · Preview" : "Sotto"
    color: c.canvas
    property var c: bridge.colors
    objectName: "mainWindow"
    property int page: 0
    property var snapshot: bridge.snapshot
    property var activity: snapshot.activity || ({
            phase: "idle"
        })
    property var result: snapshot.result || null
    property var shortcut: snapshot.shortcut || ({})
    readonly property bool shortcutBlocked: !!shortcut.changing || (!!shortcut.check && !!shortcut.check.blocked)
    property bool shortcutCheckPending: false
    property bool finishShortcutCheckAfterReply: false
    property bool microphoneTestStarting: false
    readonly property bool microphoneTestActive: microphoneTestStarting || (busy && activity.trigger === "test")
    property var feedback: snapshot.feedback || ({})
    function duration(seconds) {
        const value = Math.max(0, Math.floor(seconds || 0));
        return Math.floor(value / 60) + ":" + String(value % 60).padStart(2, "0");
    }
    readonly property string limitNotice: feedback.limitReached ? "Stopped at the recording limit" : activity.phase === "recording" && feedback.remainingSeconds !== undefined && feedback.remainingSeconds !== null && feedback.remainingSeconds <= 30 ? "Recording stops in " + duration(feedback.remainingSeconds) : ""
    property bool busy: snapshot.busy || false
    onBusyChanged: {
        if (!busy && bridge.connected && !snapshot.setupRequired)
            bridge.request("connection");
    }
    property var sources: ({
            items: [],
            next: null
        })
    property bool wasConnected: false
    property int connectionRevision: -1
    property bool sourcesChecked: false
    property string serverConnection: "Checking server"
    readonly property string connection: bridge.connected ? (snapshot.setupRequired ? "Dictation needs setup" : serverConnection) : bridge.connectionStatus === "setupRequired" ? "Dictation needs setup" : bridge.connectionStatus === "connecting" ? "Connecting dictation…" : "Dictation unavailable"
    property string notice: ""
    property bool serverReady: false
    property var pages: ["Dictation", "History", "Microphone", "Server preferences", "This computer"]
    palette.window: c.canvas
    palette.windowText: c.ink
    palette.base: c.surface
    palette.text: c.ink
    palette.button: c.surface
    palette.buttonText: c.ink
    palette.highlight: c.accent
    palette.highlightedText: c.onAccent
    palette.mid: c.line
    palette.dark: c.line
    font.family: "Sans Serif"
    font.pixelSize: 15
    function refresh() {
        if (!bridge.connected) {
            bridge.request("snapshot");
            return;
        }
        if (snapshot.setupRequired)
            return;
        bridge.request("connection");
        bridge.request("sources");
        bridge.request("shortcuts");
    }
    function startMicrophoneTest() {
        microphoneTestStarting = true;
        bridge.request("test");
    }
    function syncMicrophoneTestStart() {
        const terminalTest = activity.trigger === "test" && ["failed", "cancelled", "completed"].includes(activity.phase);
        if ((busy && activity.trigger === "test") || terminalTest)
            microphoneTestStarting = false;
    }
    function startShortcutCheck() {
        shortcutCheckPending = true;
        finishShortcutCheckAfterReply = false;
        bridge.request("checkShortcut");
    }
    function finishShortcutCheck() {
        if (shortcutCheckPending) {
            finishShortcutCheckAfterReply = true;
        } else if (shortcut.check && shortcut.check.active) {
            bridge.request("endShortcutCheck");
        }
    }
    function messageFor(phase) {
        if (phase === "preparing")
            return "Starting microphone…";
        if (phase === "recording")
            return "Listening.";
        if (phase === "processing")
            return feedback.processingStage === "proofreading" ? "Refining text…" : feedback.processingStage === "queued" ? "Waiting to transcribe…" : "Transcribing…";
        if (phase === "delivering")
            return "Delivering text…";
        if (phase === "failed")
            return "Dictation interrupted";
        if (phase === "cancelled")
            return "Dictation cancelled";
        if (phase === "completed")
            return result && result.delivery === "inserted" ? "Inserted at your cursor" : result && result.delivery === "uncertain" ? "Check your text field" : "Text ready to copy";
        return "Hold to dictate.";
    }
    Component.onCompleted: {
        wasConnected = bridge.connected;
        refresh();
    }
    Connections {
        target: bridge
        function onSnapshotChanged() {
            if (!bridge.connected) {
                app.microphoneTestStarting = false;
                app.notice = "";
                app.sourcesChecked = false;
                app.serverReady = false;
                app.sources = {
                    items: [],
                    next: null
                };
            } else if (!app.wasConnected || app.connectionRevision !== (bridge.snapshot.connectionRevision || 0)) {
                app.connectionRevision = bridge.snapshot.connectionRevision || 0;
                app.sourcesChecked = false;
                app.serverReady = false;
                app.sources = {
                    items: [],
                    next: null
                };
                app.serverConnection = "Checking server";
                app.refresh();
            }
            app.syncMicrophoneTestStart();
            app.wasConnected = bridge.connected;
        }
        function onReply(action, data) {
            if (action === "checkShortcut") {
                app.shortcutCheckPending = false;
                if (app.finishShortcutCheckAfterReply) {
                    app.finishShortcutCheckAfterReply = false;
                    bridge.request("endShortcutCheck");
                }
            }
            if (action === "saveConnection") {
                app.sourcesChecked = false;
                app.serverReady = false;
                app.serverConnection = "Checking server";
                app.sources = {
                    items: [],
                    next: null
                };
                bridge.request("snapshot");
            }
            if (action === "connection") {
                app.serverConnection = data.ready ? "Server online" : data.message || "Server not ready";
                app.serverReady = data.ready;
            }
            if (action === "sources") {
                app.sources = data;
                app.sourcesChecked = true;
            }
            if (["arm", "disarm", "saveSources"].includes(action))
                app.notice = action.startsWith("save") ? "Changes saved." : "Destination updated.";
        }
        function onFailed(action, message) {
            if (action === "test")
                app.microphoneTestStarting = false;
            if (action === "checkShortcut") {
                app.shortcutCheckPending = false;
                app.finishShortcutCheckAfterReply = false;
            }
            if (!bridge.connected)
                return;
            // Receiver controls display their errors beside the affected settings.
            if (["history", "historyAudio", "deleteHistory", "preferences", "savePreferences", "processingDefaults", "saveMicrophones", "testConnection", "saveConnection", "receiver", "saveButton", "arm", "disarm", "shortcuts", "saveShortcut", "checkShortcut", "endShortcutCheck"].includes(action))
                return;
            if (action === "connection") {
                app.serverConnection = "Server unavailable";
                app.serverReady = false;
            } else if (action === "sources") {
                app.sourcesChecked = false;
                app.sources = {
                    items: [],
                    next: null
                };
            } else
                app.notice = message;
        }
    }
    Timer {
        interval: 5000
        running: app.visible && bridge.connected
        repeat: true
        onTriggered: app.refresh()
    }
    RowLayout {
        anchors.fill: parent
        spacing: 0
        Rectangle {
            Layout.preferredWidth: 234
            Layout.fillHeight: true
            color: app.c.sidebar
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 20
                spacing: 8
                RowLayout {
                    Layout.topMargin: 14
                    Layout.bottomMargin: 34
                    spacing: 12
                    Image {
                        source: "../mark.svg"
                        Layout.preferredWidth: 44
                        Layout.preferredHeight: 44
                    }
                    SLabel {
                        ui: app
                        text: "Sotto"
                        font.family: "Serif"
                        font.pixelSize: 37
                        font.weight: Font.DemiBold
                    }
                }
                Repeater {
                    model: app.pages
                    Button {
                        required property int index
                        required property string modelData
                        Layout.fillWidth: true
                        Layout.preferredHeight: 50
                        text: modelData
                        Accessible.name: text
                        onClicked: app.page = index
                        contentItem: RowLayout {
                            spacing: 12
                            Image {
                                Layout.preferredWidth: 24
                                Layout.preferredHeight: 24
                                Accessible.ignored: true
                                source: "data:image/svg+xml," + encodeURIComponent('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="' + app.c.accent + '" stroke-width="1.65" stroke-linecap="round" stroke-linejoin="round"><path d="' + ["M3 10v4m4-8v12m5-16v20m5-16v12m4-8v4", "M3 11a9 9 0 1 1 2 7M3 4v7h7m2-5v6l4 2", "M9 5a3 3 0 0 1 6 0v7a3 3 0 0 1-6 0V5Zm-3 6v1a6 6 0 0 0 12 0v-1m-6 7v4m-4 0h8", "M4 3h16v7H4zM4 14h16v7H4zM7 6h1m-1 11h1m4-11h6m-6 11h6", "M3 3h18v13H3zM8 21h8m-4-5v5"][index] + '"/></svg>')
                            }
                            SLabel {
                                ui: app
                                text: modelData
                                font.pixelSize: 15
                                font.weight: app.page === index ? Font.DemiBold : Font.Normal
                                color: app.page === index ? app.c.ink : app.c.muted
                                Layout.fillWidth: true
                            }
                        }
                        background: Rectangle {
                            radius: 9
                            color: app.page === index ? app.c.tint : "transparent"
                            border.width: parent.activeFocus ? 2 : 0
                            border.color: app.c.accent
                        }
                    }
                }
                Item {
                    Layout.fillHeight: true
                }
                SLabel {
                    ui: app
                    text: bridge.preview ? "Preview · sample data" : app.connection
                    font.pixelSize: 12
                    color: app.c.muted
                    Layout.fillWidth: true
                }
                SLabel {
                    ui: app
                    text: "Sotto for Linux"
                    font.pixelSize: 11
                    color: app.c.muted
                }
            }
        }
        Rectangle {
            Layout.preferredWidth: 1
            Layout.fillHeight: true
            color: app.c.line
        }
        ColumnLayout {
            Layout.fillHeight: true
            Layout.fillWidth: true
            Layout.margins: 32
            spacing: 16
            Rectangle {
                objectName: "connectionBanner"
                visible: !!app.snapshot.setupRequired || (!bridge.connected && bridge.connectionStatus !== "connecting")
                Layout.fillWidth: true
                implicitHeight: offline.implicitHeight + 24
                radius: 10
                color: app.c.tint
                SLabel {
                    id: offline
                    ui: app
                    anchors.fill: parent
                    anchors.margins: 12
                    text: app.snapshot.setupRequired ? "Set up your server connection in This computer to start dictating." : bridge.connectionStatus === "setupRequired" ? "Start background dictation, then open This computer to set up your server connection." : "Dictation is unavailable. Sotto couldn’t connect to its background service. Try reconnecting in This computer."
                }
            }
            Rectangle {
                objectName: "actionNotice"
                visible: bridge.connected && app.notice.length > 0
                Layout.fillWidth: true
                implicitHeight: noticeRow.implicitHeight + 16
                radius: 10
                color: app.c.tint
                RowLayout {
                    id: noticeRow
                    anchors.fill: parent
                    anchors.margins: 8
                    SLabel {
                        ui: app
                        text: app.notice
                        Layout.fillWidth: true
                        Accessible.role: Accessible.AlertMessage
                    }
                    SButton {
                        ui: app
                        text: "Dismiss"
                        onClicked: app.notice = ""
                    }
                }
            }
            Loader {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: app.page !== 2 && app.page !== 3
                sourceComponent: [dictation, history, null, null, computer][app.page]
            }
            Loader {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: app.page === 2
                // Keep microphone drafts and in-flight saves when visiting another page.
                property bool opened: false
                onVisibleChanged: if (visible) opened = true
                active: opened || visible
                sourceComponent: microphone
            }
            Loader {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: app.page === 3
                // Keep shared drafts and in-flight saves when visiting another page.
                property bool opened: false
                onVisibleChanged: if (visible) opened = true
                active: opened || visible
                sourceComponent: preferences
            }
        }
    }
    Component {
        id: dictation
        Dictation {
            ui: app
        }
    }
    Component {
        id: history
        History {
            ui: app
        }
    }
    Component {
        id: microphone
        Microphone {
            ui: app
        }
    }
    Component {
        id: preferences
        Preferences {
            ui: app
        }
    }
    Component {
        id: computer
        Computer {
            ui: app
        }
    }
    Hud {
        ui: app
    }
}
