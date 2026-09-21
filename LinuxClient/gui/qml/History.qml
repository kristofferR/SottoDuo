import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ColumnLayout {
    id: root
    required property var ui
    property var records: []
    property var selected: null
    property string cursor: ""
    property bool loading: false
    property bool append: false
    spacing: 20
    function load(older) {
        if (loading)
            return;
        append = older;
        loading = true;
        bridge.request("history", older ? {
            before: cursor
        } : {});
    }
    Component.onCompleted: load(false)
    Connections {
        target: bridge
        function onReply(action, data) {
            if (action !== "history")
                return;
            root.records = root.append ? root.records.concat(data.items) : data.items;
            root.cursor = data.nextCursor || "";
            root.loading = false;
            root.selected = root.records.length ? root.records[0] : null;
        }
        function onFailed(action, message) {
            if (action === "history")
                root.loading = false;
        }
        function onSnapshotChanged() {
            if (!bridge.connected) {
                root.records = [];
                root.selected = null;
            }
        }
    }
    RowLayout {
        SLabel {
            ui: root.ui
            text: "History"
            font.pixelSize: 28
            font.weight: Font.DemiBold
            Layout.fillWidth: true
        }
        SButton {
            ui: root.ui
            text: "Refresh"
            enabled: !root.loading && bridge.connected
            onClicked: root.load(false)
        }
    }
    SLabel {
        ui: root.ui
        text: "Shared history · All computers"
        color: root.ui.c.muted
        font.pixelSize: 13
    }
    RowLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: 24
        ListView {
            Layout.preferredWidth: 235
            Layout.fillHeight: true
            clip: true
            model: root.records
            spacing: 8
            ScrollBar.vertical: ScrollBar {}
            delegate: ItemDelegate {
                required property var modelData
                width: ListView.view.width
                implicitHeight: summary.implicitHeight + 26
                onClicked: root.selected = modelData
                contentItem: ColumnLayout {
                    id: summary
                    spacing: 8
                    SLabel {
                        ui: root.ui
                        text: new Date(modelData.createdAt).toLocaleString()
                        font.pixelSize: 11
                        color: root.ui.c.muted
                        Layout.fillWidth: true
                    }
                    SLabel {
                        ui: root.ui
                        text: modelData.insertionText || modelData.previewText || modelData.status
                        maximumLineCount: 3
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                    SLabel {
                        ui: root.ui
                        text: modelData.device.name
                        font.pixelSize: 11
                        color: root.ui.c.muted
                    }
                }
                background: Rectangle {
                    radius: 10
                    color: root.selected && root.selected.id === modelData.id ? root.ui.c.tint : root.ui.c.surface
                    border.color: parent.activeFocus ? root.ui.c.accent : root.ui.c.line
                }
            }
            SLabel {
                ui: root.ui
                anchors.centerIn: parent
                width: parent.width
                text: root.loading ? "Loading history…" : "No dictations to show."
                visible: root.records.length === 0
                color: root.ui.c.muted
            }
        }
        Rectangle {
            Layout.fillHeight: true
            implicitWidth: 1
            color: root.ui.c.line
        }
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 16
            RowLayout {
                SLabel {
                    ui: root.ui
                    text: root.selected ? root.selected.device.name : "Your words, together"
                    Layout.fillWidth: true
                    color: root.ui.c.muted
                }
                SButton {
                    ui: root.ui
                    text: "Copy"
                    enabled: !!root.selected && !!root.selected.insertionText
                    onClicked: {
                        bridge.copy(root.selected.insertionText);
                        root.ui.notice = "Copied.";
                    }
                }
            }
            ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                TextArea {
                    readOnly: true
                    selectByMouse: true
                    wrapMode: TextEdit.Wrap
                    textFormat: TextEdit.PlainText
                    padding: 0
                    background: null
                    color: root.ui.c.ink
                    font.pixelSize: 20
                    text: root.selected ? root.selected.insertionText || root.selected.previewText || "No transcript was produced." : "Select a dictation to read its transcript."
                }
            }
            SLabel {
                ui: root.ui
                text: root.selected ? "Status: " + root.selected.status + " · Delivery: " + (root.selected.delivery ? root.selected.delivery.status : "not reported") : ""
                font.pixelSize: 12
                color: root.ui.c.muted
                Layout.fillWidth: true
            }
        }
    }
    SButton {
        ui: root.ui
        text: root.loading ? "Loading…" : "Load older"
        enabled: root.cursor.length > 0 && !root.loading
        onClicked: root.load(true)
    }
}
