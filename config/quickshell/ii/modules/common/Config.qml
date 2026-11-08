pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common.functions

Singleton {
    id: root
    property string filePath: Directories.shellConfigPath
    property alias options: configOptionsJsonAdapter
    // Pristine schema defaults; never written to disk.
    readonly property ConfigOptions defaults: ConfigOptions {}
    property bool ready: false
    property int readWriteDelay: 50 // milliseconds
    // Synchronous writes (a few ms for this file). An async write re-applies the
    // data it wrote to Config.options when it finishes, undoing any change made
    // while it was in flight; the next write then sees no difference and the
    // change is lost (tests/test_config_write_race.py).
    property bool blockWrites: true

    function setNestedValue(nestedKey, value) {
        let keys = nestedKey.split(".");
        let obj = root.options;
        let parents = [obj];

        // Traverse and collect parent objects
        for (let i = 0; i < keys.length - 1; ++i) {
            if (!obj[keys[i]] || typeof obj[keys[i]] !== "object") {
                obj[keys[i]] = {};
            }
            obj = obj[keys[i]];
            parents.push(obj);
        }

        // Convert value to correct type using JSON.parse when safe
        let convertedValue = value;
        if (typeof value === "string") {
            let trimmed = value.trim();
            if (trimmed === "true" || trimmed === "false" || !isNaN(Number(trimmed))) {
                try {
                    convertedValue = JSON.parse(trimmed);
                } catch (e) {
                    convertedValue = value;
                }
            }
        }

        obj[keys[keys.length - 1]] = convertedValue;
    }

    Timer {
        id: fileReloadTimer
        interval: root.readWriteDelay
        repeat: false
        onTriggered: {
            // A change still waiting for fileWriteTimer is newer than the file:
            // reloading now would put the old value back and the write would
            // then save that. That write brings the file up to date instead.
            if (fileWriteTimer.running)
                return;
            configFileView.reload();
            // Apply the file before returning, so a change cannot land between
            // the read and the moment its result replaces Config.options.
            configFileView.waitForJob();
        }
    }

    Timer {
        id: fileWriteTimer
        interval: root.readWriteDelay
        repeat: false
        onTriggered: {
            configFileView.writeAdapter()
        }
    }

    FileView {
        id: configFileView
        path: root.filePath
        watchChanges: true
        blockWrites: root.blockWrites
        onFileChanged: fileReloadTimer.restart()
        onAdapterUpdated: fileWriteTimer.restart()
        onLoaded: root.ready = true
        onLoadFailed: error => {
            if (error == FileViewError.FileNotFound) {
                writeAdapter();
            }
        }

        ConfigOptions {
            id: configOptionsJsonAdapter
        }
    }
}
