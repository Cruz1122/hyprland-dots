import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services
import qs.modules.settings.core
import qs.modules.settings.components

SettingsPage {
    id: advancedPage
    pageId: "advanced"

    readonly property string configPath: FileUtils.trimFileProtocol(Directories.shellConfigPath)

    actions: ({
        openConfig: entry => Quickshell.execDetached(["xdg-open", advancedPage.configPath]),
        copyConfigPath: entry => Quickshell.execDetached(["wl-copy", advancedPage.configPath])
    })
    infoValues: ({
        "info.advanced.configPath": advancedPage.configPath
    })
    customDelegates: ({
        "info.advanced.diagnostics": diagnostics,
        "info.advanced.resetAll": resetAll
    })

    Component {
        id: diagnostics

        ColumnLayout {
            id: diag
            property var row: null
            readonly property string configDir: FileUtils.trimFileProtocol(Directories.config)
            readonly property var paths: [
                { label: Translation.tr("Shell settings"), value: advancedPage.configPath },
                { label: Translation.tr("Hyprland settings"), value: `${diag.configDir}/hypr/custom/shell-settings.lua` },
                { label: Translation.tr("Idle settings"), value: `${diag.configDir}/hypr/custom/shell-idle.conf` },
                { label: Translation.tr("Monitors"), value: `${diag.configDir}/hypr/monitors.lua` },
                { label: Translation.tr("Shell folder"), value: FileUtils.trimFileProtocol(Quickshell.shellPath("")) }
            ]
            readonly property var backends: [
                { name: "config", label: Translation.tr("Shell configuration") },
                { name: "hyprland", label: Translation.tr("Hyprland") },
                { name: "idle", label: Translation.tr("Idle and lock") },
                { name: "display", label: Translation.tr("Displays") },
                { name: "mime", label: Translation.tr("Default apps") },
                { name: "audio", label: Translation.tr("Audio") },
                { name: "power", label: Translation.tr("Power") },
                { name: "ipc", label: Translation.tr("Main shell (IPC)") }
            ]

            // Availability is per backend; any entry of the backend tells it.
            function status(name) {
                void SettingsStore.revision;
                const e = SettingsRegistry.allEntries().find(x => x.backend === name);
                if (!e)
                    return Translation.tr("No settings use it");
                return SettingsStore.isAvailable(e.key) ? Translation.tr("Available") : Translation.tr(SettingsStore.unavailableReason(e.key));
            }

            spacing: 4

            Repeater {
                model: diag.paths
                delegate: DiagnosticLine {
                    required property var modelData
                    name: modelData.label
                    value: modelData.value
                }
            }

            Item { implicitHeight: 6 }

            Repeater {
                model: diag.backends
                delegate: DiagnosticLine {
                    required property var modelData
                    name: modelData.label
                    value: diag.status(modelData.name)
                }
            }
        }
    }

    component DiagnosticLine: RowLayout {
        id: line
        property string name: ""
        property string value: ""
        Layout.fillWidth: true
        spacing: 12

        StyledText {
            Layout.preferredWidth: 160
            text: line.name
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.smaller
            elide: Text.ElideRight
        }

        StyledText {
            Layout.fillWidth: true
            text: line.value
            textFormat: Text.PlainText
            wrapMode: Text.WrapAnywhere
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colOnLayer1
        }
    }

    // Two steps: the button asks for confirmation; confirming copies
    // config.json next to itself and only then resets, so a failed backup
    // leaves every setting untouched.
    Component {
        id: resetAll

        ColumnLayout {
            id: reset
            property var row: null
            property bool confirming: false
            property string status: ""
            property string backupPath: ""

            function stamp() {
                const d = new Date();
                const pad = n => String(n).padStart(2, "0");
                return `${d.getFullYear()}${pad(d.getMonth() + 1)}${pad(d.getDate())}-${pad(d.getHours())}${pad(d.getMinutes())}${pad(d.getSeconds())}`;
            }

            function start() {
                reset.confirming = false;
                reset.backupPath = `${advancedPage.configPath}.bak-${reset.stamp()}`;
                backup.command = ["cp", "--", advancedPage.configPath, reset.backupPath];
                backup.running = true;
            }

            function resetConfig() {
                let ok = true;
                const seen = {};
                for (const e of SettingsRegistry.allEntries()) {
                    if (e.backend !== "config")
                        continue;
                    for (const key of (e.type === "custom" && e.keys ? e.keys : [e.key])) {
                        if (seen[key] || !SettingsStore.isAvailable(key) || !SettingsStore.isModified(key))
                            continue;
                        seen[key] = true;
                        ok = SettingsStore.reset(key) && ok;
                    }
                }
                return ok;
            }

            spacing: 8

            Process {
                id: backup
                onExited: (code, status) => {
                    if (code !== 0) {
                        reset.status = Translation.tr("Could not back up the configuration file; nothing was reset.");
                        return;
                    }
                    const ok = reset.resetConfig();
                    reset.status = ok ? Translation.tr("Settings reset. Backup saved to %1").arg(reset.backupPath)
                        : Translation.tr("Some settings could not be reset. Backup saved to %1").arg(reset.backupPath);
                }
            }

            SettingsButton {
                visible: !reset.confirming
                kind: "danger"
                iconName: "restart_alt"
                text: Translation.tr("Reset everything")
                enabled: !backup.running
                onClicked: {
                    reset.status = "";
                    reset.confirming = true;
                }
            }

            Rectangle {
                visible: reset.confirming
                Layout.fillWidth: true
                implicitHeight: confirmLayout.implicitHeight + 24
                radius: SettingsMetrics.cardRadius
                color: Appearance.colors.colErrorContainer

                ColumnLayout {
                    id: confirmLayout
                    anchors {
                        left: parent.left
                        right: parent.right
                        verticalCenter: parent.verticalCenter
                        leftMargin: 16
                        rightMargin: 12
                    }
                    spacing: 8

                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Every shell setting goes back to its default. A copy of the current file is kept next to it.")
                        wrapMode: Text.Wrap
                        color: Appearance.colors.colOnErrorContainer
                    }

                    RowLayout {
                        Layout.alignment: Qt.AlignRight
                        spacing: 8

                        SettingsButton {
                            kind: "text"
                            text: Translation.tr("Cancel")
                            onClicked: reset.confirming = false
                        }

                        SettingsButton {
                            kind: "danger"
                            iconName: "restart_alt"
                            text: Translation.tr("Back up and reset")
                            onClicked: reset.start()
                        }
                    }
                }
            }

            StyledText {
                visible: reset.status.length > 0
                Layout.fillWidth: true
                text: reset.status
                textFormat: Text.PlainText
                wrapMode: Text.WrapAnywhere
                color: Appearance.colors.colSubtext
            }
        }
    }
}
