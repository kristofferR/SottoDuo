import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Group {
    id: root

    required property var editor
    property var lists: []
    property int selectedIndex: 0
    property int structureRevision: 0
    readonly property var selectedList: lists[selectedIndex] || null
    onSelectedListChanged: listName.text = selectedList ? selectedList.name : ""
    readonly property bool confirming: removeDialog.visible
    readonly property int wordCount: {
        structureRevision;
        return lists.reduce((total, list) => {
            return total + (list.entries || []).length;
        }, 0);
    }

    function reset() {
        lists = editor.draft?.preferences?.dictionary?.lists || [];
        selectedIndex = Math.min(Math.max(0, selectedIndex), Math.max(0, lists.length - 1));
        structureRevision++;
    }

    function uniqueID() {
        return "linux-" + Date.now() + "-" + Math.random().toString(36).slice(2);
    }

    function replaceLists(next) {
        editor.draft.preferences.dictionary.lists = next;
        lists = next;
        structureRevision++;
        editor.changed();
    }

    function addList() {
        replaceLists(lists.concat([{
            "id": uniqueID(),
            "name": "New list",
            "entries": []
        }]));
        selectedIndex = lists.length - 1;
    }

    function editWord(id, key, value) {
        const entry = selectedList.entries.find(entry => entry.id === id);
        if (entry) {
            entry[key] = value;
            editor.changed();
        }
    }

    function addWord() {
        selectedList.entries = (selectedList.entries || []).concat([{
            "id": uniqueID(),
            "term": "",
            "aliases": [],
            "isPriority": false
        }]);
        structureRevision++;
        editor.changed();
        wordList.positionViewAtEnd();
    }

    objectName: "dictionaryEditor"
    title: "Dictionary · shared"
    Component.onCompleted: reset()

    Connections {
        function onDraftChanged() {
            root.reset();
        }

        target: root.editor
    }

    Setting {
        ui: root.ui
        title: "List"
        detail: root.wordCount + " of 500 words · up to 32 lists"

        ComboBox {
            objectName: "dictionaryListPicker"
            implicitWidth: 220
            model: {
                root.structureRevision;
                return root.lists.map((list) => {
                    return list.name || "Unnamed list";
                });
            }
            currentIndex: root.selectedIndex
            enabled: root.editor.editable && root.lists.length > 0
            onActivated: root.selectedIndex = currentIndex
        }

    }

    RowLayout {
        Layout.margins: 12

        SButton {
            ui: root.ui
            objectName: "addDictionaryList"
            text: "Add list"
            enabled: root.editor.editable && root.lists.length < 32
            onClicked: root.addList()
        }

        SButton {
            ui: root.ui
            text: "Remove list"
            enabled: root.editor.editable && !!root.selectedList
            onClicked: {
                removeDialog.listID = root.selectedList.id;
                removeDialog.listName = root.selectedList.name;
                removeDialog.open();
            }
        }

    }

    TextField {
        id: listName

        objectName: "dictionaryListName"
        Layout.fillWidth: true
        Layout.margins: 12
        visible: !!root.selectedList
        enabled: root.editor.editable
        text: root.selectedList ? root.selectedList.name : ""
        placeholderText: "List name"
        placeholderTextColor: root.ui.c.muted
        Accessible.name: "Dictionary list name"
        selectByMouse: true
        onTextEdited: {
            root.selectedList.name = text;
            root.editor.changed();
        }
        onEditingFinished: root.structureRevision++
    }

    SLabel {
        ui: root.ui
        Layout.fillWidth: true
        Layout.margins: 12
        text: "Preferred spellings correct capitalization automatically. Add narrow replacement phrases, one per line. Priority words are suggested first when model space is limited."
        color: root.ui.c.muted
    }

    ListView {
        id: wordList

        objectName: "dictionaryWords"
        Layout.fillWidth: true
        Layout.preferredHeight: count ? Math.min(420, count * 175) : 0
        Layout.leftMargin: 12
        Layout.rightMargin: 12
        clip: true
        spacing: 10
        model: {
            root.structureRevision;
            return root.selectedList ? root.selectedList.entries || [] : [];
        }

        ScrollBar.vertical: ScrollBar {
        }

        delegate: ColumnLayout {
            id: word

            required property var modelData

            width: wordList.width - 16
            height: 165
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
                    onTextEdited: {
                        root.editWord(word.modelData.id, "term", text);
                    }
                }

                CheckBox {
                    objectName: "dictionaryPriority"
                    text: "Priority"
                    checked: !!word.modelData.isPriority
                    enabled: root.editor.editable
                    onClicked: {
                        root.editWord(word.modelData.id, "isPriority", checked);
                    }
                }

                SButton {
                    ui: root.ui
                    text: "Remove"
                    enabled: root.editor.editable
                    onClicked: {
                        root.selectedList.entries = root.selectedList.entries.filter((entry) => {
                            return entry.id !== word.modelData.id;
                        });
                        root.structureRevision++;
                        root.editor.changed();
                    }
                }

            }

            ScrollView {
                Layout.fillWidth: true
                Layout.preferredHeight: 105

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
                    onTextChanged: {
                        if (activeFocus) {
                            root.editWord(word.modelData.id, "aliases", text.split("\n").map((value) => {
                                return value.trim();
                            }).filter((value) => {
                                return value.length > 0;
                            }));
                        }
                    }
                }

            }

        }

    }

    RowLayout {
        Layout.margins: 12

        SButton {
            ui: root.ui
            objectName: "addDictionaryWord"
            text: "Add word"
            enabled: root.editor.editable && !!root.selectedList && root.wordCount < 500
            onClicked: root.addWord()
        }

        SLabel {
            ui: root.ui
            text: root.selectedList ? (root.selectedList.entries || []).length ? "" : "This list is empty." : "Add a list to begin."
            color: root.ui.c.muted
        }

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
                        root.replaceLists(root.lists.filter((list) => {
                            return list.id !== removeDialog.listID;
                        }));
                        root.selectedIndex = Math.min(root.selectedIndex, Math.max(0, root.lists.length - 1));
                        removeDialog.close();
                    }
                }

            }

        }

    }

}
