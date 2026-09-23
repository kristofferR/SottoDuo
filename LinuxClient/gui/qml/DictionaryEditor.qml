import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Group {
    id: root

    required property var editor
    property var lists: []
    property var expandedIDs: []
    property int structureRevision: 0
    property int nameRevision: 0
    readonly property bool confirming: removeDialog.visible
    readonly property int wordCount: {
        structureRevision;
        return lists.reduce((total, list) => total + (list.entries || []).length, 0);
    }

    function reset() {
        lists = editor.draft?.preferences?.dictionary?.lists || [];
        expandedIDs = expandedIDs.filter(id => lists.some(list => list.id === id));
        structureRevision++;
    }

    function uniqueID() {
        return "linux-" + Date.now() + "-" + Math.random().toString(36).slice(2);
    }

    function listFor(id) {
        return lists.find(list => list.id === id);
    }

    function replaceLists(next) {
        editor.draft.preferences.dictionary.lists = next;
        lists = next;
        structureRevision++;
        editor.changed();
    }

    function toggleList(id) {
        expandedIDs = expandedIDs.includes(id) ? expandedIDs.filter(value => value !== id) : expandedIDs.concat(id);
    }

    function addList() {
        const list = { id: uniqueID(), name: "New list", entries: [] };
        replaceLists(lists.concat(list));
        expandedIDs = expandedIDs.concat(list.id);
    }

    function addWord(listID) {
        const list = listFor(listID);
        if (!list)
            return;
        list.entries = (list.entries || []).concat({ id: uniqueID(), term: "", aliases: [], isPriority: false });
        structureRevision++;
        editor.changed();
    }

    function editWord(listID, entryID, key, value) {
        const entry = listFor(listID)?.entries.find(item => item.id === entryID);
        if (entry) {
            entry[key] = value;
            editor.changed();
        }
    }

    function removeWord(listID, entryID) {
        const list = listFor(listID);
        if (!list)
            return;
        list.entries = list.entries.filter(entry => entry.id !== entryID);
        structureRevision++;
        editor.changed();
    }

    objectName: "dictionaryEditor"
    title: "Dictionary · shared"
    Component.onCompleted: reset()

    Connections {
        target: root.editor
        function onDraftChanged() { root.reset(); }
    }

    SLabel {
        ui: root.ui
        text: root.wordCount + " of 500 words · up to 32 lists"
        color: root.ui.c.muted
        Layout.margins: 12
    }

    Repeater {
        model: {
            root.structureRevision;
            return root.lists;
        }
        ColumnLayout {
            id: listSection
            required property var modelData
            readonly property string listID: modelData.id
            readonly property bool expanded: root.expandedIDs.includes(listID)
            Layout.fillWidth: true
            spacing: 0

            Setting {
                ui: root.ui
                title: {
                    root.nameRevision;
                    return (listSection.expanded ? "⌄  " : "›  ") + (listSection.modelData.name || "New list");
                }
                detail: (listSection.modelData.entries || []).length + " words"
                SButton {
                    ui: root.ui
                    objectName: "dictionaryListToggle_" + listSection.listID
                    text: listSection.expanded ? "Collapse" : "Expand"
                    Accessible.name: (listSection.expanded ? "Collapse " : "Expand ") + (listSection.modelData.name || "New list")
                    onClicked: root.toggleList(listSection.listID)
                }
            }

            ColumnLayout {
                visible: listSection.expanded
                Layout.fillWidth: true
                Layout.leftMargin: 14
                Layout.rightMargin: 14
                spacing: 10

                TextField {
                    objectName: "dictionaryListName_" + listSection.listID
                    Layout.fillWidth: true
                    enabled: root.editor.editable
                    text: listSection.modelData.name
                    placeholderText: "List name"
                    placeholderTextColor: root.ui.c.muted
                    Accessible.name: "Dictionary list name"
                    selectByMouse: true
                    onTextEdited: {
                        const list = root.listFor(listSection.listID);
                        if (list) {
                            list.name = text;
                            root.nameRevision++;
                            root.editor.changed();
                        }
                    }
                }

                SLabel {
                    ui: root.ui
                    Layout.fillWidth: true
                    text: "Preferred spellings correct capitalization automatically. Add narrow replacement phrases, one per line. Priority words are suggested first when model space is limited."
                    color: root.ui.c.muted
                    font.pixelSize: 13
                }

                ListView {
                    id: wordList
                    objectName: "dictionaryWords_" + listSection.listID
                    Layout.fillWidth: true
                    Layout.preferredHeight: count ? Math.min(420, count * 125) : 0
                    clip: true
                    spacing: 10
                    model: {
                        root.structureRevision;
                        return root.listFor(listSection.listID)?.entries || [];
                    }
                    ScrollBar.vertical: ScrollBar {}
                    delegate: ColumnLayout {
                        id: word
                        required property var modelData
                        width: wordList.width - 12
                        height: 115
                        spacing: 5
                        RowLayout {
                            TextField {
                                objectName: "dictionaryTerm"
                                Layout.fillWidth: true
                                text: word.modelData.term
                                placeholderText: "Preferred spelling"
                                placeholderTextColor: root.ui.c.muted
                                Accessible.name: "Preferred spelling"
                                enabled: root.editor.editable
                                selectByMouse: true
                                onTextEdited: root.editWord(listSection.listID, word.modelData.id, "term", text)
                            }
                            CheckBox {
                                objectName: "dictionaryPriority"
                                text: "Priority"
                                checked: !!word.modelData.isPriority
                                enabled: root.editor.editable
                                onClicked: root.editWord(listSection.listID, word.modelData.id, "isPriority", checked)
                            }
                            SButton {
                                ui: root.ui
                                text: "Remove"
                                Accessible.name: "Remove " + (word.modelData.term || "word")
                                enabled: root.editor.editable
                                onClicked: root.removeWord(listSection.listID, word.modelData.id)
                            }
                        }
                        ScrollView {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 58
                            TextArea {
                                objectName: "dictionaryAliases"
                                text: (word.modelData.aliases || []).join("\n")
                                placeholderText: "Replacement phrases, one per line (up to 8)"
                                placeholderTextColor: root.ui.c.muted
                                Accessible.name: "Replacement phrases"
                                textFormat: TextEdit.PlainText
                                wrapMode: TextEdit.Wrap
                                selectByMouse: true
                                enabled: root.editor.editable
                                onTextChanged: if (activeFocus) root.editWord(listSection.listID, word.modelData.id, "aliases", text.split("\n").map(value => value.trim()).filter(value => value.length > 0))
                            }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    SButton {
                        ui: root.ui
                        objectName: "addDictionaryWord"
                        text: "Add word"
                        enabled: root.editor.editable && root.wordCount < 500
                        onClicked: root.addWord(listSection.listID)
                    }
                    SLabel {
                        ui: root.ui
                        visible: !(listSection.modelData.entries || []).length
                        text: "This list is empty."
                        color: root.ui.c.muted
                        Layout.fillWidth: true
                    }
                    SButton {
                        ui: root.ui
                        text: "Remove list"
                        enabled: root.editor.editable
                        onClicked: {
                            removeDialog.listID = listSection.listID;
                            removeDialog.listName = listSection.modelData.name;
                            removeDialog.open();
                        }
                    }
                }
            }
        }
    }

    SButton {
        ui: root.ui
        objectName: "addDictionaryList"
        text: "Add list"
        Layout.margins: 12
        enabled: root.editor.editable && root.lists.length < 32
        onClicked: root.addList()
    }

    Dialog {
        id: removeDialog
        property string listID: ""
        property string listName: ""
        title: "Remove “" + listName + "”?"
        parent: Overlay.overlay
        anchors.centerIn: parent
        modal: true
        width: 390
        contentItem: ColumnLayout {
            SLabel {
                ui: root.ui
                Layout.fillWidth: true
                text: "The list and its words will be removed from every device when you save shared preferences."
            }
            RowLayout {
                SButton {
                    ui: root.ui
                    text: "Cancel"
                    onClicked: removeDialog.close()
                }
                SButton {
                    ui: root.ui
                    text: "Remove list"
                    enabled: root.editor.editable
                    onClicked: {
                        root.replaceLists(root.lists.filter(list => list.id !== removeDialog.listID));
                        root.expandedIDs = root.expandedIDs.filter(id => id !== removeDialog.listID);
                        removeDialog.close();
                    }
                }
            }
        }
    }
}
