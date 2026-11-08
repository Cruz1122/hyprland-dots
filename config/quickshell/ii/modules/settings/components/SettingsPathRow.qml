import QtQuick
import QtQuick.Dialogs
import QtQuick.Layouts
import qs.modules.common
import qs.services

// Path text field with a folder or file picker (entry.pick: "folder" | "file").
SettingsTextRow {
    id: row

    readonly property bool pickFile: row.entry?.pick === "file"

    controlPreferredWidth: 340

    function pickedPath(url) {
        return decodeURIComponent(String(url).replace(/^file:\/\//, ""));
    }

    SettingsIconButton {
        iconName: row.pickFile ? "draft" : "folder_open"
        tooltip: row.pickFile ? Translation.tr("Choose a file") : Translation.tr("Choose a folder")
        onClicked: row.pickFile ? fileDialog.open() : folderDialog.open()
    }

    FolderDialog {
        id: folderDialog
        title: row.label
        currentFolder: row.stored.length > 0 ? `file://${row.stored}` : ""
        onAccepted: {
            row.field.text = row.pickedPath(folderDialog.selectedFolder);
            row.commitField();
        }
    }

    FileDialog {
        id: fileDialog
        title: row.label
        onAccepted: {
            row.field.text = row.pickedPath(fileDialog.selectedFile);
            row.commitField();
        }
    }
}
