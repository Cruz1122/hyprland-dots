import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs.modules.settings.core
import "../backends/IpcLogic.js" as IpcLogic

// AI quota accounts live in the main shell (AiQuotaUsage runs the private
// `ai-quotas.py serve` backend there). The settings process must not start a
// second backend, so it only asks the shell's quota panel, over IPC, to
// connect a provider or to open; accounts are chosen in that panel.
ColumnLayout {
    id: root

    property var row: null
    readonly property bool canConnect: (SettingsStore.revision, SettingsStore.hasCapability("ipc:aiQuotaConnect"))
    readonly property bool canOpen: (SettingsStore.revision, SettingsStore.hasCapability("ipc:aiQuotaPanelToggle"))
    readonly property var providers: [
        { id: "codex", name: "Codex / ChatGPT", icon: "terminal" },
        { id: "opencode", name: "OpenCode Go", icon: "code" },
        { id: "antigravity", name: "Antigravity · Google AI Pro", icon: "rocket_launch" },
        { id: "zed", name: "Zed", icon: "edit_note" },
        { id: "cursor", name: "Cursor", icon: "arrow_selector_tool" },
        { id: "claude", name: "Claude", icon: "smart_toy" }
    ]

    function run(name, args) {
        const argv = IpcLogic.namedCallArgv(Quickshell.shellPath(""), name, args);
        if (argv)
            Quickshell.execDetached(argv);
    }

    spacing: 8

    StyledText {
        Layout.fillWidth: true
        text: root.canConnect
            ? Translation.tr("Credentials typed in the panel are stored in the system keyring, never in the configuration file.")
            : Translation.tr("Start the shell to connect accounts.")
        wrapMode: Text.Wrap
        color: Appearance.colors.colSubtext
        font.pixelSize: Appearance.font.pixelSize.smaller
    }

    Flow {
        Layout.fillWidth: true
        spacing: 8

        Repeater {
            model: root.providers

            delegate: SettingsButton {
                required property var modelData
                kind: "tonal"
                iconName: modelData.icon
                text: modelData.name
                enabled: root.canConnect
                Accessible.name: Translation.tr("Connect %1").arg(modelData.name)
                onClicked: root.run("aiQuotaConnect", [modelData.id])
            }
        }
    }

    SettingsButton {
        kind: "text"
        iconName: "open_in_new"
        text: Translation.tr("Open the quota panel")
        enabled: root.canOpen
        onClicked: root.run("aiQuotaPanelToggle", [])
    }
}
