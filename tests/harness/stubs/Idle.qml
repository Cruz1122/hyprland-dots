pragma Singleton
import QtQuick
import Quickshell

// Harness stub for services/Idle.qml. The real service attaches its
// IdleInhibitor to a layer-shell PanelWindow, which has no backend under
// QT_QPA_PLATFORM=offscreen and aborts module loading. The public API is kept
// so callers bind exactly as they do in the live shell.
Singleton {
    id: root

    property bool inhibit: false

    function toggleInhibit(active = null) {
        root.inhibit = active !== null ? active : !root.inhibit;
    }
}
