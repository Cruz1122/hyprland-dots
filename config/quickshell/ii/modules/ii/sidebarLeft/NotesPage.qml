import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

Item {
    id: root

    property string draggedId: ""
    property string dropTargetId: ""
    property bool dropAfter: false
    property bool dragActive: false
    property real dragStartY: 0

    function displayNotes() {
        return Notes.list.slice(0).sort((a, b) => {
            if (a.pinned !== b.pinned)
                return a.pinned ? -1 : 1;
            return Notes.list.indexOf(a) - Notes.list.indexOf(b);
        });
    }

    function syncNotesModel() {
        const ordered = root.displayNotes();

        if (root.draggedId.length > 0 && ordered.length === noteCardModel.count) {
            const sourceIndex = noteCardModelIndex(root.draggedId);
            const destination = ordered.findIndex(note => note.id === root.draggedId);
            if (sourceIndex >= 0 && destination >= 0 && sourceIndex !== destination) {
                noteCardModel.move(sourceIndex, destination, 1);
                return;
            }
        }

        for (let i = noteCardModel.count - 1; i >= 0; --i) {
            const id = noteCardModel.get(i).noteId;
            if (!ordered.some(note => note.id === id))
                noteCardModel.remove(i);
        }

        for (let destination = 0; destination < ordered.length; ++destination) {
            const note = ordered[destination];
            let source = -1;
            for (let i = destination; i < noteCardModel.count; ++i) {
                if (noteCardModel.get(i).noteId === note.id) {
                    source = i;
                    break;
                }
            }

            if (source < 0) {
                noteCardModel.insert(destination, {
                    noteId: note.id,
                    content: Notes.contentFor(note.id),
                    pinned: note.pinned,
                });
                continue;
            }

            if (source !== destination)
                noteCardModel.move(source, destination, 1);
            const row = noteCardModel.get(destination);
            if (row.content !== Notes.contentFor(note.id))
                noteCardModel.setProperty(destination, "content", Notes.contentFor(note.id));
            if (row.pinned !== note.pinned)
                noteCardModel.setProperty(destination, "pinned", note.pinned);
        }
    }

    function noteCardModelIndex(id) {
        for (let i = 0; i < noteCardModel.count; ++i) {
            if (noteCardModel.get(i).noteId === id)
                return i;
        }
        return -1;
    }

    function updateDropTargetAt(pointerY) {
        if (!root.dragActive || root.draggedId.length === 0)
            return;

        const ordered = root.displayNotes();
        const sourceIndex = ordered.findIndex(note => note.id === root.draggedId);
        if (sourceIndex < 0)
            return;

        let targetIndex = -1;
        for (let i = 0; i < ordered.length; ++i) {
            const item = notesList.itemAtIndex(i);
            if (item && pointerY >= item.y && pointerY <= item.y + item.height) {
                targetIndex = i;
                break;
            }
        }
        if (targetIndex < 0 || targetIndex === sourceIndex) {
            root.dropTargetId = "";
            return;
        }

        const source = ordered[sourceIndex];
        const target = ordered[targetIndex];
        if (source.pinned !== target.pinned) {
            root.dropTargetId = "";
            return;
        }

        const targetItem = notesList.itemAtIndex(targetIndex);
        if (!targetItem) {
            root.dropTargetId = "";
            return;
        }

        const pointerPastMidpoint = pointerY >= targetItem.y + targetItem.height / 2;
        const crossedTarget = sourceIndex < targetIndex ? pointerPastMidpoint : !pointerPastMidpoint;
        root.dropTargetId = crossedTarget ? target.id : "";
        root.dropAfter = sourceIndex < targetIndex;
    }

    function finishDrag() {
        if (root.dragActive && root.dropTargetId.length > 0) {
            Notes.move(root.draggedId, root.dropTargetId, root.dropAfter);
            Notes.flush();
        }
        root.draggedId = "";
        root.dropTargetId = "";
        root.dropAfter = false;
        root.dragActive = false;
    }

    function copyText(content) {
        const escaped = StringUtils.shellSingleQuoteEscape(String(content || ""));
        Quickshell.execDetached(["bash", "-c", `printf '%s' '${escaped}' | wl-copy`]);
    }

    ListModel {
        id: noteCardModel
    }

    Connections {
        target: Notes
        function onListChanged() { root.syncNotesModel(); }
        function onReadyChanged() { root.syncNotesModel(); }
    }

    Component.onCompleted: root.syncNotesModel()

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 8

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            StyledListView {
                id: notesList
                anchors.fill: parent
                anchors.bottomMargin: 52
                spacing: 8
                clip: true
                enabled: Notes.ready
                interactive: root.draggedId.length === 0
                animateAppearance: false
                animateMovement: true
                // Keep moved notes visible while their order animates.
                model: noteCardModel

                delegate: Rectangle {
                    id: noteCard
                    required property int index
                    required property string noteId
                    required property string content
                    required property bool pinned
                    property bool beingDragged: root.draggedId === noteId && root.dragActive
                    property bool isDropTarget: root.dropTargetId === noteId
                    width: notesList.width
                    implicitHeight: editor.implicitHeight + 32
                    radius: Appearance.rounding.small
                    color: (beingDragged || isDropTarget) ? Appearance.colors.colLayer2Hover : Appearance.colors.colLayer2
                    scale: beingDragged ? 1.03 : 1
                    border.width: (pinned || beingDragged || isDropTarget) ? 1 : 0
                    border.color: isDropTarget ? Appearance.colors.colPrimary : Appearance.colors.colSecondary
                    z: beingDragged ? 2 : 1

                    Behavior on scale {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 6

                        RowLayout {
                            z: 10
                            Layout.fillWidth: true

                            MaterialSymbol {
                                text: noteCard.pinned ? "push_pin" : "drag_indicator"
                                color: noteCard.pinned ? Appearance.colors.colSecondary : Appearance.colors.colSubtext
                                iconSize: Appearance.font.pixelSize.normal
                            }

                            Item { Layout.fillWidth: true }

                            IconToolbarButton {
                                id: copyButton
                                property bool justCopied: false
                                text: justCopied ? "check" : "content_copy"
                                implicitWidth: 30
                                colBackground: "transparent"
                                colBackgroundHover: Appearance.colors.colLayer3Hover
                                onClicked: {
                                    root.copyText(Notes.contentFor(noteCard.noteId));
                                    justCopied = true;
                                    copyReset.restart();
                                }

                                Timer {
                                    id: copyReset
                                    interval: 700
                                    onTriggered: copyButton.justCopied = false
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: {
                                        root.copyText(Notes.contentFor(noteCard.noteId));
                                        copyButton.justCopied = true;
                                        copyReset.restart();
                                    }
                                }
                            }
                            IconToolbarButton {
                                text: noteCard.pinned ? "push_pin" : "keep"
                                implicitWidth: 30
                                colBackground: "transparent"
                                colBackgroundHover: Appearance.colors.colLayer3Hover
                                onClicked: Notes.togglePinned(noteCard.noteId)
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: Notes.togglePinned(noteCard.noteId)
                                }
                            }
                            IconToolbarButton {
                                text: "delete"
                                implicitWidth: 30
                                colBackground: "transparent"
                                colBackgroundHover: Appearance.colors.colErrorContainerHover
                                onClicked: Notes.remove(noteCard.noteId)
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: Notes.remove(noteCard.noteId)
                                }
                            }
                        }

                        StyledTextArea {
                            id: editor
                            Layout.fillWidth: true
                            Layout.preferredHeight: 48
                            Layout.maximumHeight: 48
                            implicitHeight: 48
                            placeholderText: Translation.tr("Write your note...")
                            textFormat: TextEdit.PlainText
                            wrapMode: TextEdit.Wrap
                            background: null
                            padding: 4
                            Component.onCompleted: text = noteCard.content
                            onTextChanged: {
                                if (activeFocus)
                                    Notes.updateContent(noteCard.noteId, text);
                            }
                            onActiveFocusChanged: {
                                if (!activeFocus)
                                    Notes.flush();
                            }
                        }
                    }

                    MouseArea {
                        id: dragArea
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: 30
                        z: 3
                        cursorShape: Qt.OpenHandCursor
                        preventStealing: true

                        onPressed: event => {
                            root.draggedId = noteCard.noteId;
                            root.dropTargetId = "";
                            root.dragActive = false;
                            root.dragStartY = dragArea.mapToItem(notesList.contentItem, event.x, event.y).y;
                        }
                        onPositionChanged: event => {
                            if (!pressed || root.draggedId !== noteCard.noteId)
                                return;
                            const pointerY = dragArea.mapToItem(notesList.contentItem, event.x, event.y).y;
                            if (!root.dragActive && Math.abs(pointerY - root.dragStartY) < 4)
                                return;
                            root.dragActive = true;
                            root.updateDropTargetAt(pointerY);
                        }
                        onReleased: root.finishDrag()
                        onCanceled: root.finishDrag()
                    }
                }
            }

            ColumnLayout {
                anchors.centerIn: notesList
                width: Math.min(notesList.width - 32, 260)
                spacing: 8
                visible: Notes.ready && Notes.list.length === 0
                z: 1

                MaterialSymbol {
                    Layout.alignment: Qt.AlignHCenter
                    text: "edit_note"
                    iconSize: Appearance.font.pixelSize.huge
                    color: Appearance.colors.colSubtext
                }

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("No notes yet")
                    color: Appearance.colors.colOnLayer1
                    font.weight: Font.DemiBold
                    horizontalAlignment: Text.AlignHCenter
                }

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Add a note to keep it here after restarting.")
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    wrapMode: Text.Wrap
                    horizontalAlignment: Text.AlignHCenter
                }
            }

            IconToolbarButton {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 4
                enabled: Notes.ready
                text: "add"
                implicitWidth: 36
                implicitHeight: 36
                colBackground: Appearance.colors.colLayer2
                colBackgroundHover: Appearance.colors.colLayer2Hover
                onClicked: Notes.add()
                z: 2
            }
        }
    }
}
