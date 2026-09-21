import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ScrollView {
    id: root
    required property var ui
    property var draft: null
    property bool dirty: false
    property bool saving: false
    clip: true
    contentWidth: availableWidth
    function edit(key, value) {
        let next = JSON.parse(JSON.stringify(draft));
        next.preferences[key] = value;
        draft = next;
        dirty = true;
    }
    Component.onCompleted: bridge.request("preferences")
    Connections {
        target: bridge
        function onReply(action, data) {
            if (action === "preferences" || action === "savePreferences") {
                root.draft = data;
                root.dirty = false;
                root.saving = false;
            }
        }
        function onFailed(action, message) {
            if (action === "savePreferences") {
                root.saving = false;
                root.ui.notice = "Could not save. Another computer may have changed these settings. Reload to compare before saving again.";
            }
        }
    }
    ColumnLayout {
        width: root.availableWidth
        spacing: 22
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
        Group {
            ui: root.ui
            title: "TRANSCRIPTION"
            enabled: !!root.draft && !root.saving
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
                    implicitWidth: 245
                    property var codes: ["auto", "en", "es", "fr", "de", "it", "pt", "nl", "ja", "zh", "ko", "hi", "ar", "pl", "ru", "uk", "sv"]
                    model: ["Detect automatically", "English", "Spanish", "French", "German", "Italian", "Portuguese", "Dutch", "Japanese", "Chinese", "Korean", "Hindi", "Arabic", "Polish", "Russian", "Ukrainian", "Swedish"]
                    currentIndex: root.draft ? codes.indexOf(root.draft.preferences.language) : 0
                    onActivated: root.edit("language", codes[currentIndex])
                }
            }
        }
        Group {
            ui: root.ui
            title: "VOCABULARY · SHARED"
            enabled: !!root.draft && !root.saving
            Setting {
                ui: root.ui
                title: "Words and phrases"
                detail: "Help Sotto recognize names and terms. Existing dictionary lists are preserved."
            }
            TextArea {
                Layout.fillWidth: true
                Layout.margins: 12
                Layout.preferredHeight: 120
                text: root.draft ? root.draft.preferences.vocabulary : ""
                placeholderText: "Sotto, PipeWire, names you use often…"
                textFormat: TextEdit.PlainText
                wrapMode: TextEdit.Wrap
                selectByMouse: true
                onTextChanged: if (activeFocus && root.draft && text !== root.draft.preferences.vocabulary)
                    root.edit("vocabulary", text)
            }
        }
        Group {
            ui: root.ui
            title: "AUDIO AND TEXT"
            enabled: !!root.draft && !root.saving
            Setting {
                ui: root.ui
                title: "Keep original audio"
                detail: "Save original recordings alongside shared dictation history."
                Switch {
                    checked: root.draft ? root.draft.preferences.keepOriginalAudio : false
                    Accessible.name: "Keep original audio"
                    onToggled: root.edit("keepOriginalAudio", checked)
                }
            }
            Setting {
                ui: root.ui
                title: "Text cleanup"
                detail: "Apply the server’s configured cleanup rules."
                Switch {
                    checked: root.draft ? root.draft.preferences.textCorrectionEnabled : false
                    Accessible.name: "Text cleanup"
                    onToggled: root.edit("textCorrectionEnabled", checked)
                }
            }
        }
        RowLayout {
            SButton {
                ui: root.ui
                text: root.saving ? "Saving…" : "Save changes"
                primary: true
                enabled: root.dirty && !root.saving && bridge.connected
                onClicked: {
                    root.saving = true;
                    bridge.request("savePreferences", {
                        value: root.draft
                    });
                }
            }
            SButton {
                ui: root.ui
                text: "Reload from server"
                enabled: !root.saving && bridge.connected
                onClicked: bridge.request("preferences")
            }
        }
        SLabel {
            ui: root.ui
            text: "Changes apply to new dictations. Reload discards your unsaved edits."
            color: root.ui.c.muted
            font.pixelSize: 12
            Layout.fillWidth: true
        }
    }
}
