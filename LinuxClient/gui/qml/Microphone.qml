import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ScrollView {
    id: root
    required property var ui
    property var draft: JSON.parse(JSON.stringify(ui.snapshot.sources || {
        mode: "automatic",
        priority: []
    }))
    property bool dirty: false
    clip: true
    contentWidth: availableWidth
    function key(value) {
        return value.hostID + "\n" + value.id;
    }
    function rank(id) {
        return draft.priority.findIndex(x => key(x) === key(id));
    }
    function changePriority(id, action) {
        let next = JSON.parse(JSON.stringify(draft));
        let index = rank(id);
        if (action === "add" && index < 0)
            next.priority.push(id);
        if (action === "remove" && index >= 0)
            next.priority.splice(index, 1);
        if (action === "up" && index > 0) {
            let previous = next.priority[index - 1];
            next.priority[index - 1] = id;
            next.priority[index] = previous;
        }
        draft = next;
        dirty = true;
    }
    function nameFor(id) {
        let found = ui.sources.items.find(s => key(s.identity) === key(id));
        return found ? found.name : id.id + " (unavailable)";
    }
    Connections {
        target: bridge
        function onReply(action, data) {
            if (action === "saveSources") {
                root.draft = data;
                root.dirty = false;
                root.ui.refresh();
            }
        }
        function onSnapshotChanged() {
            if (!root.dirty && root.ui.snapshot.sources)
                root.draft = JSON.parse(JSON.stringify(root.ui.snapshot.sources));
        }
    }
    ColumnLayout {
        width: root.availableWidth
        spacing: 22
        SLabel {
            ui: root.ui
            text: "Microphone"
            font.pixelSize: 28
            font.weight: Font.DemiBold
        }
        SLabel {
            ui: root.ui
            text: "Choose where your voice comes from."
            color: root.ui.c.muted
        }
        Group {
            ui: root.ui
            Setting {
                ui: root.ui
                title: "Choose input"
                ComboBox {
                    implicitWidth: 245
                    model: ["Automatic · priority list", "System default", "Fixed input"]
                    currentIndex: ["automatic", "systemDefault", "fixed"].indexOf(root.draft.mode)
                    onActivated: {
                        root.draft = Object.assign({}, root.draft, {
                            mode: ["automatic", "systemDefault", "fixed"][currentIndex]
                        });
                        root.dirty = true;
                    }
                }
            }
            Setting {
                ui: root.ui
                title: "Next dictation"
                detail: root.dirty ? "Save changes to update the next input." : "Availability is checked again when dictation starts."
                SLabel {
                    ui: root.ui
                    text: root.ui.sources.next ? root.ui.sources.next.name : "None available"
                    Layout.maximumWidth: 230
                }
            }
        }
        Group {
            ui: root.ui
            title: "INPUT PRIORITY · ONLY THIS COMPUTER"
            visible: root.draft.mode === "automatic"
            Repeater {
                model: root.draft.priority
                Setting {
                    required property var modelData
                    required property int index
                    ui: root.ui
                    title: (index + 1) + ". " + root.nameFor(modelData)
                    SButton {
                        ui: root.ui
                        text: "Move up"
                        enabled: index > 0
                        onClicked: root.changePriority(modelData, "up")
                    }
                    SButton {
                        ui: root.ui
                        text: "Remove"
                        onClicked: root.changePriority(modelData, "remove")
                    }
                }
            }
            Setting {
                ui: root.ui
                title: "System fallback"
                detail: "After preferred inputs, Sotto uses an eligible microphone on the configured capture host."
            }
        }
        Group {
            ui: root.ui
            title: "AVAILABLE INPUTS"
            Repeater {
                model: root.ui.sources.items
                Setting {
                    required property var modelData
                    ui: root.ui
                    title: modelData.name
                    detail: modelData.eligible ? "Available · " + modelData.transport : "Unavailable or not ready"
                    SButton {
                        ui: root.ui
                        text: root.draft.mode === "fixed" ? (root.draft.fixed && root.key(root.draft.fixed) === root.key(modelData.identity) ? "Selected" : "Choose") : root.rank(modelData.identity) >= 0 ? "In priority list" : "Add"
                        enabled: root.draft.mode !== "systemDefault" && (root.draft.mode === "fixed" || root.rank(modelData.identity) < 0)
                        onClicked: {
                            if (root.draft.mode === "fixed") {
                                root.draft = Object.assign({}, root.draft, {
                                    fixed: modelData.identity
                                });
                                root.dirty = true;
                            } else
                                root.changePriority(modelData.identity, "add");
                        }
                    }
                }
            }
            Setting {
                ui: root.ui
                visible: root.ui.sources.items.length === 0
                title: "No inputs reported"
                detail: "Check the server connection, then refresh."
            }
        }
        SLabel {
            ui: root.ui
            text: "A recording keeps the microphone it started with. If that input is lost, start a new take to use a fallback. Pairing-button dictation always uses its receiver."
            color: root.ui.c.muted
            font.pixelSize: 13
            Layout.fillWidth: true
        }
        RowLayout {
            SButton {
                ui: root.ui
                text: "Save changes"
                primary: true
                enabled: root.dirty && !root.ui.busy && bridge.connected && (root.draft.mode !== "fixed" || !!root.draft.fixed)
                onClicked: bridge.request("saveSources", {
                    value: root.draft
                })
            }
            SButton {
                ui: root.ui
                text: "Refresh inputs"
                onClicked: root.ui.refresh()
            }
        }
    }
}
