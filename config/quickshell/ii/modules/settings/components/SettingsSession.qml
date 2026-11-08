pragma Singleton

import QtQuick

// UI state of the settings window that lives for the session only (never
// persisted): which rows have their help open, and requests to reveal a row
// that SettingsShell forwards to settings.qml (another page included).
QtObject {
    id: root

    // key -> true while that row's help is open. Mutated in place; bindings
    // track helpRevision.
    readonly property var _openHelp: ({})
    property int helpRevision: 0

    signal revealRequested(string key)

    function isHelpOpen(key) {
        void root.helpRevision;
        return root._openHelp[key] === true;
    }

    function setHelpOpen(key, open) {
        if (!key || (root._openHelp[key] === true) === open)
            return;
        root._openHelp[key] = open;
        root.helpRevision++;
    }

    function requestReveal(key) {
        if (key)
            root.revealRequested(key);
    }
}
