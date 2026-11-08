import QtQuick
import qs.services

// Runs page.actions[entry.action](entry). entry.actionLabel names the button
// (defaults to "Open"); entry.actionKind is a SettingsButton kind.
SettingsRow {
    id: row

    readonly property var handler: row.page?.actions?.[row.entry?.action ?? ""] ?? null

    extraEnabled: typeof row.handler === "function"
    extraDisabledReason: typeof row.handler === "function" ? "" : Translation.tr("Not available")
    focusVisible: false
    activateHandler: () => row.run()
    interactHandler: () => false

    function run() {
        if (typeof row.handler === "function")
            row.handler(row.entry);
    }

    SettingsButton {
        kind: row.entry?.actionKind ?? "tonal"
        iconName: row.entry?.actionIcon ?? ""
        text: Translation.tr(row.entry?.actionLabel ?? "Open")
        onClicked: row.run()
    }
}
