pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    readonly property int schemaVersion: 1
    property list<var> list: []
    property var pendingContents: ({})
    property bool ready: false
    property bool hasPendingChanges: false
    property bool loadingLegacy: false

    function newId() {
        return `${Date.now()}-${Math.floor(Math.random() * 1000000)}`;
    }

    function normalizedNotes(value) {
        if (!Array.isArray(value))
            return [];

        return value.filter(note => note !== null && typeof note === "object").map(note => ({
            id: String(note.id || root.newId()),
            content: String(note.content || ""),
            pinned: Boolean(note.pinned),
        }));
    }

    function persist() {
        if (!root.ready)
            return;
        root.hasPendingChanges = true;
        saveTimer.restart();
    }

    function write() {
        const savedNotes = root.list.map(note => ({
            id: note.id,
            content: root.pendingContents[note.id] ?? note.content,
            pinned: note.pinned,
        }));
        notesFile.setText(JSON.stringify({
            version: root.schemaVersion,
            notes: savedNotes,
        }, null, 2));
        root.hasPendingChanges = false;
    }

    function flush() {
        if (!root.hasPendingChanges)
            return;
        saveTimer.stop();
        root.write();
    }

    function add(content = "") {
        root.list = root.list.concat([{
            id: root.newId(),
            content: content,
            pinned: false,
        }]);
        root.persist();
    }

    function updateContent(id, content) {
        const note = root.list.find(item => item.id === id);
        if (note && (root.pendingContents[id] ?? note.content) !== content) {
            root.pendingContents[id] = content;
            root.persist();
        }
    }

    function contentFor(id) {
        const note = root.list.find(item => item.id === id);
        return note ? (root.pendingContents[id] ?? note.content) : "";
    }

    function togglePinned(id) {
        root.list = root.list.map(note => note.id === id
            ? { id: note.id, content: note.content, pinned: !note.pinned }
            : note);
        root.persist();
    }

    function remove(id) {
        root.list = root.list.filter(note => note.id !== id);
        delete root.pendingContents[id];
        root.persist();
    }

    function move(id, targetId, after = false) {
        const updated = root.list.slice(0).sort((a, b) => {
            if (a.pinned !== b.pinned)
                return a.pinned ? -1 : 1;
            return root.list.indexOf(a) - root.list.indexOf(b);
        });
        const sourceIndex = updated.findIndex(note => note.id === id);
        let targetIndex = updated.findIndex(note => note.id === targetId);
        if (sourceIndex < 0 || targetIndex < 0 || sourceIndex === targetIndex)
            return;

        const [item] = updated.splice(sourceIndex, 1);
        if (sourceIndex < targetIndex)
            targetIndex -= 1;
        if (after)
            targetIndex += 1;
        updated.splice(targetIndex, 0, item);
        root.list = updated;
        root.persist();
    }

    function loadLegacy() {
        root.loadingLegacy = true;
        legacyNotesFile.reload();
    }

    function migrateLegacy() {
        const content = legacyNotesFile.text();
        root.list = content.length > 0 ? [{ id: root.newId(), content: content, pinned: false }] : [];
        root.write();
        root.ready = true;
        console.log("[Notes] Migrated legacy notes.txt");
    }

    Component.onCompleted: {
        mkdirProcess.running = true;
    }

    Component.onDestruction: root.flush()

    Process {
        id: mkdirProcess
        command: ["mkdir", "-p", `${Directories.state}/user`]
        onExited: notesFile.reload()
    }

    Timer {
        id: saveTimer
        interval: 150
        repeat: false
        onTriggered: root.write()
    }

    FileView {
        id: notesFile
        path: Qt.resolvedUrl(Directories.notesJsonPath)
        onLoaded: {
            try {
                const data = JSON.parse(notesFile.text());
                const value = data && typeof data === "object" ? (data.notes ?? data) : [];
                root.list = root.normalizedNotes(value);
                root.pendingContents = {};
                root.ready = true;
            } catch (error) {
                console.log("[Notes] Invalid notes.json: " + error);
                Quickshell.execDetached(["cp", Directories.notesJsonPath, `${Directories.notesJsonPath}.corrupt-${Date.now()}`]);
                root.list = [];
                root.ready = true;
            }
        }
        onLoadFailed: error => {
            if (error === FileViewError.FileNotFound) {
                root.loadLegacy();
            } else {
                console.log("[Notes] Error loading notes.json: " + error);
            }
        }
    }

    FileView {
        id: legacyNotesFile
        path: Qt.resolvedUrl(Directories.notesPath)
        blockLoading: true // Load only when notes.json is missing, to avoid overwriting it.
        onLoaded: {
            if (!root.loadingLegacy)
                return;
            root.loadingLegacy = false;
            root.migrateLegacy();
        }
        onLoadFailed: error => {
            if (!root.loadingLegacy)
                return;
            root.loadingLegacy = false;
            if (error === FileViewError.FileNotFound) {
                root.list = [];
                root.write();
                root.ready = true;
            } else {
                console.log("[Notes] Error loading legacy notes.txt: " + error);
            }
        }
    }
}
