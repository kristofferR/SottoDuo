import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ColumnLayout {
    id: root

    required property var ui
    property var draft: null
    property var latest: null
    property string draftServer: ""
    property bool dirty: false
    property int editRevision: 0
    property bool saving: false
    property bool reading: false
    property bool discardOnRead: false
    property bool changedRemotely: false
    property string message: ""
    property string defaultPrompt: ""
    property var health: null
    readonly property bool editable: !!draft && bridge.connected && !ui.snapshot.setupRequired && !ui.snapshot.connectionChanging && !saving && !discardOnRead && !bridge.preview && draftServer === ui.snapshot.server

    function clone(value) {
        return JSON.parse(JSON.stringify(value));
    }

    function changed() {
        editRevision++;
        dirty = true;
        message = "";
    }

    function edit(key, value) {
        if (draft) {
            draft.preferences[key] = value;
            changed();
        }
    }

    function load(value) {
        const next = clone(value);
        if (!next.preferences.dictionary)
            next.preferences.dictionary = { lists: [] };
        draft = next;
        latest = clone(value);
        draftServer = ui.snapshot.server;
        cleanup.text = next.preferences.proofreadingPrompt !== undefined ? next.preferences.proofreadingPrompt : defaultPrompt;
        vocabulary.text = next.preferences.vocabulary || "";
        dirty = false;
        changedRemotely = false;
        message = "";
    }

    function read(discard) {
        if (reading || saving || !bridge.connected)
            return ;

        discardOnRead = discard;
        reading = true;
        bridge.request("preferences");
    }

    function reload() {
        if (dirty)
            discardDialog.open();
        else
            read(true);
    }

    function modelDetail(model) {
        if (!model)
            return "Checking server models…";

        return model.modelID + " · " + model.backend + (model.message ? "\n" + model.message : "");
    }

    objectName: "processingSettings"
    Component.onCompleted: {
        read(false);
        bridge.request("processingDefaults");
        bridge.request("connection");
    }

    Connections {
        function onReply(action, data) {
            if (action === "processingDefaults")
                root.defaultPrompt = data.proofreadingPrompt;

            if (action === "connection")
                root.health = data;

            if (action === "preferences") {
                root.reading = false;
                // A late read cannot replace a newer save or erase a local draft.
                if (root.latest && data.revision < root.latest.revision) {
                    root.discardOnRead = false;
                    return ;
                }
                root.latest = root.clone(data);
                if (root.discardOnRead || (!root.dirty && !dictionary.confirming && !root.saving && (!root.draft || data.revision !== root.draft.revision)))
                    root.load(data);
                else if (root.draft && data.revision !== root.draft.revision)
                    root.changedRemotely = true;
                root.discardOnRead = false;
            }
            if (action === "savePreferences" && root.saving) {
                root.saving = false;
                root.load(data);
                root.message = "Shared preferences saved. Changes apply to new dictations.";
            }
        }

        function onFailed(action, message) {
            if (action === "savePreferences") {
                root.saving = false;
                root.message = message;
                root.read(false);
            }
            if (action === "preferences") {
                root.reading = false;
                root.discardOnRead = false;
                root.message = "Could not load shared preferences. Your edits are kept. Check the connection and try reloading.";
            }
            if (action === "connection")
                root.health = null;

        }

        function onSnapshotChanged() {
            if (!bridge.connected) {
                root.health = null;
                root.saving = false;
                root.reading = false;
                root.discardOnRead = false;
            }
            if (root.draft && bridge.connected && root.draftServer !== root.ui.snapshot.server) {
                root.changedRemotely = true;
                root.latest = null;
                root.health = null;
                root.message = "The connected server changed. Discard and reload its shared preferences before editing.";
            }
        }

        target: bridge
    }

    Timer {
        interval: 5000
        repeat: true
        running: root.visible && root.ui.visible && bridge.connected
        onTriggered: {
            root.read(false);
            if (!root.defaultPrompt)
                bridge.request("processingDefaults");

        }
    }

    SLabel {
        ui: root.ui
        text: "Server preferences"
        font.pixelSize: 28
        font.weight: Font.DemiBold
    }

    SLabel {
        ui: root.ui
        text: "Shared by every computer using this server."
        color: root.ui.c.muted
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 9
        Rectangle {
            Layout.preferredWidth: 8
            Layout.preferredHeight: 8
            radius: 4
            color: root.ui.serverReady || bridge.preview ? "#4ade80" : root.ui.c.muted
        }
        SLabel {
            ui: root.ui
            text: root.ui.connection
            Layout.fillWidth: true
        }
        SLabel {
            ui: root.ui
            objectName: "preferencesServerAddress"
            text: root.ui.snapshot.server || ""
            visible: text.length > 0
            color: root.ui.c.muted
            font.pixelSize: 13
            wrapMode: Text.NoWrap
            elide: Text.ElideMiddle
            Layout.preferredWidth: Math.min(220, root.width * 0.35)
        }
    }

    RowLayout {
        SButton {
            ui: root.ui
            objectName: "saveProcessingSettings"
            text: root.saving ? "Saving…" : "Save changes"
            primary: true
            enabled: root.editable && root.dirty && !root.changedRemotely
            onClicked: {
                root.saving = true;
                root.message = "";
                bridge.request("savePreferences", {
                    "value": root.draft,
                    "server": root.draftServer
                });
            }
        }

        SButton {
            ui: root.ui
            objectName: "reloadProcessingSettings"
            text: root.reading ? "Checking…" : root.dirty ? "Discard and reload" : "Reload from server"
            enabled: !root.reading && !root.saving && bridge.connected
            onClicked: root.reload()
        }

    }

    SLabel {
        ui: root.ui
        objectName: "processingMessage"
        Layout.fillWidth: true
        visible: text.length > 0
        text: root.message || (root.changedRemotely ? "Shared preferences changed on another device. Your edits are kept here. Discard and reload to continue." : "")
    }

    ScrollView {
        id: settingsScroll

        objectName: "processingScroll"
        Layout.fillWidth: true
        Layout.fillHeight: true
        contentWidth: availableWidth
        clip: true

        ColumnLayout {
            width: settingsScroll.availableWidth
            spacing: 22

            Group {
                ui: root.ui
                title: "Server models"

                Setting {
                    ui: root.ui
                    title: "Speech recognition"
                    detail: root.modelDetail(root.health ? root.health.speech : null)

                    SLabel {
                        ui: root.ui
                        objectName: "speechModelReadiness"
                        text: root.health && root.health.speech ? root.health.speech.ready ? "Ready" : "Not ready" : "Unavailable"
                        color: root.ui.c.muted
                    }

                }

                Setting {
                    ui: root.ui
                    title: "Text cleanup"
                    detail: root.modelDetail(root.health ? root.health.proofreading : null)

                    SLabel {
                        ui: root.ui
                        text: root.health && root.health.proofreading ? root.health.proofreading.ready ? "Ready" : "Not ready" : "Unavailable"
                        color: root.ui.c.muted
                    }

                }

            }

            Group {
                ui: root.ui
                title: "Transcription"
                enabled: root.editable

                Setting {
                    ui: root.ui
                    title: "Recognition"

                    ComboBox {
                        implicitWidth: 245
                        model: ["Automatic", "Cloud", "Local"]
                        currentIndex: root.draft ? ["automatic", "cloud", "local"].indexOf(root.draft.preferences.recognitionMode || "automatic") : 0
                        onActivated: root.edit("recognitionMode", ["automatic", "cloud", "local"][currentIndex])
                    }

                }

                Setting {
                    ui: root.ui
                    title: "Language"

                    ComboBox {
                        property var codes: ["auto", "en", "es", "fr", "de", "it", "pt", "nl", "ja", "zh", "ko", "hi", "ar", "pl", "ru", "uk", "sv"]

                        implicitWidth: 245
                        model: ["Detect automatically", "English", "Spanish", "French", "German", "Italian", "Portuguese", "Dutch", "Japanese", "Chinese", "Korean", "Hindi", "Arabic", "Polish", "Russian", "Ukrainian", "Swedish"]
                        currentIndex: root.draft ? codes.indexOf(root.draft.preferences.language) : 0
                        onActivated: root.edit("language", codes[currentIndex])
                    }

                }

            }

            Group {
                ui: root.ui
                title: "Text cleanup"
                enabled: root.editable

                Setting {
                    ui: root.ui
                    title: "Text cleanup"
                    detail: "Apply these instructions to new dictations."

                    Switch {
                        checked: root.draft ? root.draft.preferences.textCorrectionEnabled : false
                        Accessible.name: "Text cleanup"
                        onClicked: root.edit("textCorrectionEnabled", checked)
                    }

                }

                Setting {
                    ui: root.ui
                    title: "Cleanup instructions"
                    detail: "Up to 4 KB. Reset changes your draft until you save."

                    SButton {
                        ui: root.ui
                        objectName: "resetCleanupPrompt"
                        text: "Reset to default"
                        enabled: {
                            root.editRevision;
                            return !!root.defaultPrompt && !!root.draft && root.draft.preferences.proofreadingPrompt !== root.defaultPrompt;
                        }
                        onClicked: {
                            root.edit("proofreadingPrompt", root.defaultPrompt);
                            root.draft = root.clone(root.draft);
                            cleanup.text = root.defaultPrompt;
                        }
                    }

                }

                ScrollView {
                    Layout.fillWidth: true
                    Layout.margins: 12
                    Layout.preferredHeight: 240

                    TextArea {
                        id: cleanup

                        objectName: "cleanupInstructions"
                        text: root.draft ? (root.draft.preferences.proofreadingPrompt !== undefined ? root.draft.preferences.proofreadingPrompt : root.defaultPrompt) : ""
                        Accessible.name: "Cleanup instructions"
                        textFormat: TextEdit.PlainText
                        wrapMode: TextEdit.Wrap
                        selectByMouse: true
                        onTextChanged: {
                            if (activeFocus && root.draft && text !== root.draft.preferences.proofreadingPrompt) {
                                root.edit("proofreadingPrompt", text);
                            }
                        }
                    }

                }

            }

            Group {
                ui: root.ui
                title: "Vocabulary · shared"
                enabled: root.editable

                Setting {
                    ui: root.ui
                    title: "Words and phrases"
                    detail: "Names and terms to help recognition, up to 16 KB."
                }

                ScrollView {
                    Layout.fillWidth: true
                    Layout.margins: 12
                    Layout.preferredHeight: 110

                    TextArea {
                        id: vocabulary

                        objectName: "recognitionVocabulary"
                        text: root.draft ? root.draft.preferences.vocabulary : ""
                        placeholderText: "Sotto, PipeWire, names you use often…"
                        placeholderTextColor: root.ui.c.muted
                        textFormat: TextEdit.PlainText
                        wrapMode: TextEdit.Wrap
                        selectByMouse: true
                        onTextChanged: {
                            if (activeFocus && root.draft && text !== root.draft.preferences.vocabulary) {
                                root.edit("vocabulary", text);
                            }
                        }
                    }

                }

            }

            Group {
                ui: root.ui
                title: "Shared history"
                enabled: root.editable

                Setting {
                    ui: root.ui
                    title: "Keep original audio"
                    detail: "Save original recordings alongside shared dictation history."

                    Switch {
                        checked: root.draft ? root.draft.preferences.keepOriginalAudio : false
                        Accessible.name: "Keep original audio"
                        onClicked: root.edit("keepOriginalAudio", checked)
                    }

                }

            }

            DictionaryEditor {
                id: dictionary

                ui: root.ui
                editor: root
            }

        }

    }

    Dialog {
        id: discardDialog

        title: "Discard unsaved shared settings?"
        parent: Overlay.overlay
        anchors.centerIn: parent
        modal: true
        width: 410

        contentItem: ColumnLayout {
            SLabel {
                ui: root.ui
                text: "Your local edits will be replaced with the latest settings from the connected server. Nothing is saved by reloading."
                Layout.fillWidth: true
            }

            RowLayout {
                SButton {
                    ui: root.ui
                    text: "Keep editing"
                    onClicked: discardDialog.close()
                }

                SButton {
                    ui: root.ui
                    text: "Discard and reload"
                    enabled: !root.reading && !root.saving && bridge.connected
                    onClicked: {
                        root.read(true);
                        discardDialog.close();
                    }
                }

            }

        }

    }

}
