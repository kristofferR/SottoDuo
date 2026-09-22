import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ScrollView {
    id: root
    objectName: "microphonePage"
    required property var ui
    property var draft: ({
            mode: "automatic",
            priority: [],
            profiles: [],
            knownInputs: []
        })
    property string revision: ""
    property bool dirty: false
    property bool pending: false
    property string message: ""
    property var seenInputs: []
    readonly property bool scopeChanged: !!ui.snapshot.microphones && (draft.server !== ui.snapshot.microphones.value.server || draft.hostID !== ui.snapshot.microphones.value.hostID)
    readonly property bool editable: bridge.connected && !bridge.preview && !ui.busy && !ui.snapshot.connectionChanging && !pending && !!revision && !scopeChanged
    readonly property var activeProfile: draft.profiles.find(p => p.id === draft.activeProfileID) || ({
            name: "Default",
            priority: []
        })
    clip: true
    contentWidth: availableWidth
    function clone(value) {
        return JSON.parse(JSON.stringify(value));
    }
    function key(value) {
        return JSON.stringify([value.hostID, value.id]);
    }
    function rememberInputs() {
        let inputs = seenInputs.slice();
        for (const source of ui.sources.items) {
            const input = {
                identity: source.identity,
                name: source.name
            };
            const index = inputs.findIndex(x => key(x.identity) === key(input.identity));
            if (index < 0)
                inputs.push(input);
            else
                inputs[index] = input;
        }
        seenInputs = inputs;
    }
    function loadSaved() {
        const saved = ui.snapshot.microphones;
        if (!saved)
            return;
        if (draft.server !== saved.value.server)
            seenInputs = [];
        draft = clone(saved.value);
        revision = saved.revision;
        dirty = false;
        message = "";
        rememberInputs();
    }
    Component.onCompleted: loadSaved()
    function rank(id) {
        return draft.priority.findIndex(x => key(x) === key(id));
    }
    function edited(next) {
        draft = next;
        dirty = true;
        message = "";
    }
    function selectProfile(id) {
        let next = clone(draft);
        next.activeProfileID = id;
        next.priority = clone(next.profiles.find(p => p.id === id).priority);
        edited(next);
    }
    function changePriority(id, action) {
        let next = clone(draft);
        const index = rank(id);
        if (action === "add" && index < 0)
            next.priority.push(id);
        if (action === "remove" && index >= 0)
            next.priority.splice(index, 1);
        if (action === "up" && index > 0)
            [next.priority[index - 1], next.priority[index]] = [next.priority[index], next.priority[index - 1]];
        if (action === "down" && index >= 0 && index < next.priority.length - 1)
            [next.priority[index + 1], next.priority[index]] = [next.priority[index], next.priority[index + 1]];
        next.profiles.find(p => p.id === next.activeProfileID).priority = clone(next.priority);
        edited(next);
    }
    function nameFor(id) {
        const live = ui.sources.items.find(s => key(s.identity) === key(id));
        const saved = seenInputs.concat(draft.knownInputs || []).find(s => key(s.identity) === key(id));
        return live ? live.name : saved ? saved.name : id.id;
    }
    function detailFor(id) {
        const live = ui.sources.items.find(s => key(s.identity) === key(id));
        return id.hostID + " · " + (live ? live.eligible ? "Available" : live.unavailableReason || "Unavailable or not ready" : "Not currently reported");
    }
    function editName(create) {
        profileDialog.creating = create;
        profileName.text = create ? "" : activeProfile.name;
        profileDialog.error = "";
        profileDialog.open();
        profileName.forceActiveFocus();
    }
    function saveName() {
        const name = profileName.text.trim();
        if (!name || draft.profiles.some(p => p.name.toLowerCase() === name.toLowerCase() && (profileDialog.creating || p.id !== draft.activeProfileID))) {
            profileDialog.error = "Choose a non-empty, unique name.";
            return;
        }
        let next = clone(draft);
        if (profileDialog.creating) {
            const id = "profile-" + Date.now() + "-" + Math.random().toString(36).slice(2);
            next.profiles.push({
                id: id,
                name: name,
                priority: []
            });
            next.activeProfileID = id;
            next.priority = [];
        } else
            next.profiles.find(p => p.id === next.activeProfileID).name = name;
        edited(next);
        profileDialog.close();
    }
    Connections {
        target: root.ui
        function onSourcesChanged() {
            root.rememberInputs();
        }
    }
    Connections {
        target: bridge
        function onReply(action, data) {
            if (action === "saveMicrophones" && root.pending) {
                root.draft = root.clone(data.value);
                root.revision = data.revision;
                root.dirty = false;
                root.pending = false;
                root.message = "Microphone settings saved. They apply to your next take.";
                bridge.request("snapshot");
                root.ui.refresh();
            }
        }
        function onFailed(action, message) {
            if (action === "saveMicrophones") {
                root.pending = false;
                root.message = message;
            }
        }
        function onSnapshotChanged() {
            if (!bridge.connected)
                root.pending = false;
            if (!root.dirty && !root.pending && !profileDialog.visible && !deleteDialog.visible && root.ui.snapshot.microphones && root.ui.snapshot.microphones.revision !== root.revision)
                root.loadSaved();
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
                    objectName: "microphoneMode"
                    implicitWidth: 245
                    model: ["Automatic · priority list", "System default", "Fixed input"]
                    currentIndex: ["automatic", "systemDefault", "fixed"].indexOf(root.draft.mode)
                    enabled: root.editable
                    onActivated: {
                        let next = root.clone(root.draft);
                        next.mode = ["automatic", "systemDefault", "fixed"][currentIndex];
                        root.edited(next);
                    }
                }
            }
            Setting {
                ui: root.ui
                title: "Next dictation"
                detail: root.dirty ? "Unsaved changes. The current settings stay active until you save." : root.ui.sources.reason || "Availability is checked again when dictation starts."
                SLabel {
                    ui: root.ui
                    objectName: "nextMicrophone"
                    text: root.ui.sources.next ? root.ui.sources.next.name : "None available"
                    Layout.maximumWidth: 230
                }
            }
            Setting {
                ui: root.ui
                visible: root.draft.mode === "fixed"
                title: root.draft.fixed ? root.nameFor(root.draft.fixed) : "Choose a fixed input below"
                detail: root.draft.fixed ? root.detailFor(root.draft.fixed) + ". Host fallback is used if this input cannot start." : "Fixed input keeps host fallback available."
            }
        }
        Group {
            ui: root.ui
            title: "Priority lists · only this computer"
            Setting {
                ui: root.ui
                title: "Saved list"
                detail: root.draft.mode === "automatic" ? "Uses the first ready microphone in this list." : "Lists are used in Automatic mode. Your current input mode is unchanged."
                ComboBox {
                    objectName: "microphoneProfilePicker"
                    implicitWidth: 205
                    model: root.draft.profiles.map(p => p.name)
                    currentIndex: root.draft.profiles.findIndex(p => p.id === root.draft.activeProfileID)
                    enabled: root.editable
                    onActivated: root.selectProfile(root.draft.profiles[currentIndex].id)
                }
            }
            RowLayout {
                Layout.margins: 12
                SButton {
                    ui: root.ui
                    text: "New list"
                    objectName: "newMicrophoneProfile"
                    enabled: root.editable && root.draft.profiles.length < 16
                    onClicked: root.editName(true)
                }
                SButton {
                    ui: root.ui
                    text: "Rename"
                    enabled: root.editable
                    onClicked: root.editName(false)
                }
                SButton {
                    ui: root.ui
                    text: "Delete"
                    objectName: "deleteMicrophoneProfile"
                    enabled: root.editable && root.draft.profiles.length > 1
                    onClicked: deleteDialog.open()
                }
            }
            Repeater {
                model: root.draft.priority
                Setting {
                    required property var modelData
                    required property int index
                    ui: root.ui
                    title: (index + 1) + ". " + root.nameFor(modelData)
                    detail: root.detailFor(modelData)
                    SButton {
                        ui: root.ui
                        text: "↑"
                        Accessible.name: "Move " + root.nameFor(modelData) + " up"
                        enabled: root.editable && index > 0
                        onClicked: root.changePriority(modelData, "up")
                    }
                    SButton {
                        ui: root.ui
                        text: "↓"
                        Accessible.name: "Move " + root.nameFor(modelData) + " down"
                        enabled: root.editable && index < root.draft.priority.length - 1
                        onClicked: root.changePriority(modelData, "down")
                    }
                    SButton {
                        ui: root.ui
                        text: "Remove"
                        enabled: root.editable
                        onClicked: root.changePriority(modelData, "remove")
                    }
                }
            }
            Setting {
                ui: root.ui
                title: "System fallback"
                detail: "After preferred inputs, Sotto uses an eligible microphone on the configured capture host. An empty list uses this fallback directly."
            }
        }
        Group {
            ui: root.ui
            title: "Available inputs"
            Repeater {
                model: root.ui.sources.items
                Setting {
                    required property var modelData
                    ui: root.ui
                    title: modelData.name
                    detail: modelData.identity.hostID + " · " + (modelData.eligible ? "Available · " + modelData.transport : modelData.unavailableReason || "Unavailable or not ready")
                    SButton {
                        ui: root.ui
                        text: root.draft.mode === "fixed" ? (root.draft.fixed && root.key(root.draft.fixed) === root.key(modelData.identity) ? "Selected" : "Choose") : root.rank(modelData.identity) >= 0 ? "In priority list" : "Add to list"
                        enabled: root.editable && (root.draft.mode === "fixed" || (root.rank(modelData.identity) < 0 && root.draft.priority.length < 32))
                        onClicked: {
                            if (root.draft.mode === "fixed") {
                                let next = root.clone(root.draft);
                                next.fixed = modelData.identity;
                                root.edited(next);
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
                detail: "Saved microphones stay in their lists. Check the server connection, then refresh."
            }
        }
        SLabel {
            ui: root.ui
            text: "A recording keeps the microphone it started with. If that input is lost, start a new take to use a fallback. Pairing-button dictation always uses its receiver."
            color: root.ui.c.muted
            font.pixelSize: 13
            Layout.fillWidth: true
        }
        SLabel {
            ui: root.ui
            text: root.scopeChanged ? "The server or capture host changed. Discard changes to reload microphone settings before editing." : root.message
            visible: text.length > 0
            Layout.fillWidth: true
        }
        RowLayout {
            SButton {
                ui: root.ui
                objectName: "saveMicrophonesButton"
                text: root.pending ? "Saving…" : "Save changes"
                primary: true
                enabled: root.dirty && root.editable && (root.draft.mode !== "fixed" || !!root.draft.fixed)
                onClicked: {
                    root.rememberInputs();
                    let value = root.clone(root.draft);
                    const inputs = root.seenInputs.slice();
                    for (const input of value.knownInputs || [])
                        if (!inputs.some(x => root.key(x.identity) === root.key(input.identity)))
                            inputs.push(input);
                    const referenced = value.profiles.flatMap(p => p.priority).concat(value.fixed ? [value.fixed] : []);
                    value.knownInputs = inputs.filter(input => referenced.some(id => root.key(id) === root.key(input.identity)));
                    root.pending = true;
                    root.message = "";
                    bridge.request("saveMicrophones", {
                        value: value,
                        revision: root.revision
                    });
                }
            }
            SButton {
                ui: root.ui
                text: "Discard changes"
                enabled: root.dirty && !root.pending
                onClicked: root.loadSaved()
            }
            SButton {
                ui: root.ui
                text: "Refresh inputs"
                onClicked: root.ui.refresh()
            }
        }
    }
    Dialog {
        id: profileDialog
        objectName: "microphoneProfileDialog"
        onClosed: if (!root.dirty)
            root.loadSaved()
        property bool creating: true
        property string error: ""
        title: creating ? "New priority list" : "Rename priority list"
        parent: Overlay.overlay
        anchors.centerIn: parent
        modal: true
        width: 380
        contentItem: ColumnLayout {
            TextField {
                id: profileName
                objectName: "microphoneProfileName"
                Layout.fillWidth: true
                placeholderText: "Desk, travel…"
                placeholderTextColor: root.ui.c.muted
                maximumLength: 80
                onAccepted: if (root.editable)
                    root.saveName()
            }
            SLabel {
                ui: root.ui
                text: profileDialog.error || "Each list remembers its own microphone order."
                Layout.fillWidth: true
            }
            RowLayout {
                SButton {
                    ui: root.ui
                    text: "Cancel"
                    onClicked: profileDialog.close()
                }
                SButton {
                    ui: root.ui
                    text: profileDialog.creating ? "Create" : "Rename"
                    enabled: root.editable && !!profileName.text.trim()
                    onClicked: root.saveName()
                }
            }
        }
    }
    Dialog {
        id: deleteDialog
        onClosed: if (!root.dirty)
            root.loadSaved()
        title: "Delete “" + root.activeProfile.name + "”?"
        parent: Overlay.overlay
        anchors.centerIn: parent
        modal: true
        width: 400
        contentItem: ColumnLayout {
            SLabel {
                ui: root.ui
                text: "This removes the saved list when you save changes. Another list will be selected. Microphones are not removed."
                Layout.fillWidth: true
            }
            RowLayout {
                SButton {
                    ui: root.ui
                    text: "Cancel"
                    onClicked: deleteDialog.close()
                }
                SButton {
                    ui: root.ui
                    text: "Delete list"
                    enabled: root.editable && root.draft.profiles.length > 1
                    onClicked: {
                        let next = root.clone(root.draft);
                        next.profiles = next.profiles.filter(p => p.id !== next.activeProfileID);
                        next.activeProfileID = next.profiles[0].id;
                        next.priority = root.clone(next.profiles[0].priority);
                        root.edited(next);
                        deleteDialog.close();
                    }
                }
            }
        }
    }
}
