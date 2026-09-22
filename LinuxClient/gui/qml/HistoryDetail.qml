import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ColumnLayout {
    id: root

    required property var ui
    required property var history
    readonly property var record: history.selected
    readonly property string transcript: record ? record.finalText || record.insertionText || record.previewText || "" : ""
    readonly property var audio: record ? record.inferenceAudio || record.originalAudio : null
    readonly property var processing: record ? record.textProcessing : null
    readonly property bool terminal: !!record && ["completed", "failed", "cancelled"].includes(record.status)

    function model(value) {
        return value ? value.modelID + " · " + value.backend : "";
    }

    function duration() {
        const value = audio && audio.sampleRate ? audio.frameCount / audio.sampleRate : record && record.importedSource ? record.importedSource.durationSeconds : undefined;
        if (value === undefined || value <= 0)
            return "";

        const seconds = Math.round(value);
        return Math.floor(seconds / 60) + ":" + String(seconds % 60).padStart(2, "0");
    }

    spacing: 12

    RowLayout {
        SLabel {
            ui: root.ui
            text: root.record ? root.record.device.name : "Your words, together"
            Layout.fillWidth: true
            color: root.ui.c.muted
        }

        SButton {
            ui: root.ui
            objectName: "copyHistory"
            text: "Copy"
            enabled: root.transcript.length > 0
            onClicked: {
                bridge.copy(root.transcript);
                root.history.message = "Copied.";
            }
        }

        SButton {
            ui: root.ui
            objectName: "deleteHistory"
            text: root.history.deleting ? "Deleting…" : "Delete"
            enabled: root.terminal && root.history.available && !root.history.acting && !root.history.loading && !bridge.preview
            onClicked: root.history.confirmDelete()
        }

    }

    SLabel {
        ui: root.ui
        Layout.fillWidth: true
        color: root.ui.c.muted
        font.pixelSize: 12
        text: root.record ? (root.record.importedSource ? "Wispr Flow · " : "Sotto · ") + root.record.status + (root.duration() ? " · " + root.duration() : "") + " · Delivery: " + (root.record.delivery ? root.record.delivery.status : "not reported") : ""
    }

    ScrollView {
        id: scroll

        Layout.fillWidth: true
        Layout.fillHeight: true
        contentWidth: availableWidth
        clip: true

        ColumnLayout {
            width: scroll.availableWidth
            spacing: 16

            SLabel {
                ui: root.ui
                Layout.fillWidth: true
                visible: !!text
                text: root.record ? root.record.error || "" : ""
            }

            TextArea {
                objectName: "historyTranscript"
                Layout.fillWidth: true
                readOnly: true
                selectByMouse: true
                wrapMode: TextEdit.Wrap
                textFormat: TextEdit.PlainText
                padding: 0
                background: null
                color: root.ui.c.ink
                font.pixelSize: 19
                text: root.record ? root.transcript || "No transcript was produced." : "Select a dictation to read its transcript."
            }

            CheckBox {
                id: original

                objectName: "showRawHistory"
                text: root.record && root.record.importedSource ? "Show original recognition (Wispr Flow)" : "Show original recognition"
                visible: !!root.record && !!root.record.rawText && root.record.rawText !== root.transcript
                onVisibleChanged: checked = false
            }

            TextArea {
                objectName: "historyRawText"
                Layout.fillWidth: true
                visible: original.visible && original.checked
                readOnly: true
                selectByMouse: true
                wrapMode: TextEdit.Wrap
                textFormat: TextEdit.PlainText
                padding: 0
                background: null
                color: root.ui.c.muted
                text: root.record ? root.record.rawText || "" : ""
            }

            SLabel {
                ui: root.ui
                Layout.fillWidth: true
                visible: !!text
                text: root.record ? root.record.formattingRejectionReason || "" : ""
            }

            SLabel {
                ui: root.ui
                Layout.fillWidth: true
                visible: !!text
                text: root.processing ? "Text cleanup: " + (root.processing.status || (root.processing.enabled ? "enabled" : "disabled")) + (root.processing.reason ? "\n" + root.processing.reason : "") : ""
            }

            CheckBox {
                id: rejected

                text: "Show rejected cleanup"
                visible: !!root.processing && root.processing.status === "rejected" && !!root.processing.proposedText
                onVisibleChanged: checked = false
            }

            TextArea {
                Layout.fillWidth: true
                visible: rejected.visible && rejected.checked
                readOnly: true
                selectByMouse: true
                wrapMode: TextEdit.Wrap
                textFormat: TextEdit.PlainText
                padding: 0
                background: null
                color: root.ui.c.muted
                text: root.processing ? root.processing.proposedText || "" : ""
            }

            SLabel {
                ui: root.ui
                Layout.fillWidth: true
                color: root.ui.c.muted
                font.pixelSize: 12
                visible: !!text
                text: root.record && root.record.recognitionHints && root.record.recognitionHints.omittedTerms.length ? "Voice vocabulary omitted: " + root.record.recognitionHints.omittedTerms.join(", ") : ""
            }

            SLabel {
                ui: root.ui
                Layout.fillWidth: true
                color: root.ui.c.muted
                font.pixelSize: 12
                visible: !!text
                text: root.record && root.record.proofreadingHints && root.record.proofreadingHints.omittedTerms.length ? "Cleanup vocabulary omitted: " + root.record.proofreadingHints.omittedTerms.join(", ") : ""
            }

            SLabel {
                ui: root.ui
                Layout.fillWidth: true
                color: root.ui.c.muted
                font.pixelSize: 12
                visible: !!text
                text: root.record && root.record.speech ? "Speech: " + root.model(root.record.speech) : ""
            }

            SLabel {
                ui: root.ui
                Layout.fillWidth: true
                color: root.ui.c.muted
                font.pixelSize: 12
                visible: !!text
                text: root.record && root.record.proofreading ? "Cleanup: " + root.model(root.record.proofreading) : ""
            }

        }

    }

    Flow {
        Layout.fillWidth: true
        spacing: 8

        SButton {
            ui: root.ui
            objectName: "openHistoryAudio"
            text: "Open audio"
            visible: !!root.record && !!root.record.inferenceAudio
            enabled: root.history.available && !root.history.acting && !bridge.preview
            onClicked: root.history.openAudio("inference")
        }

        SButton {
            ui: root.ui
            text: "Open original"
            visible: !!root.record && !!root.record.originalAudio
            enabled: root.history.available && !root.history.acting && !bridge.preview
            onClicked: root.history.openAudio("original")
        }

        SButton {
            ui: root.ui
            text: "Open Wispr Flow audio"
            visible: !!root.record && !!root.record.importedSource && (root.record.importedSource.artifactNames || []).includes("source.wav")
            enabled: root.history.available && !root.history.acting && !bridge.preview
            onClicked: root.history.openAudio("imported")
        }

    }

}
