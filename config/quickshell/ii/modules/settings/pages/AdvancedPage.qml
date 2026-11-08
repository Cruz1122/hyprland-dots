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
import "AdvancedLogic.js" as AdvancedLogic

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
        "info.advanced.hyprlandErrors": configErrors,
        "info.advanced.resetAll": resetAll
    })

    // `hyprctl -j configerrors` (argv, read-only) each time the page opens and
    // on "Check again"; AdvancedLogic.parseConfigErrors drops the [""] that
    // means "no errors".
    Component {
        id: configErrors

        ColumnLayout {
            id: errs
            objectName: "configErrors"
            readonly property bool hyprland: (Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") ?? "").length > 0
            // "unavailable", "checking", "none", "errors" or "failed".
            property string status: errs.hyprland ? "checking" : "unavailable"
            property var errors: []
            property int hidden: 0
            readonly property string summary: errs.status === "unavailable" ? Translation.tr("Hyprland is not running")
                : errs.status === "checking" ? Translation.tr("Checking…")
                : errs.status === "none" ? Translation.tr("No errors")
                : errs.status === "failed" ? Translation.tr("Could not read the errors from Hyprland.")
                : errs.errors.length + errs.hidden === 1 ? Translation.tr("1 error")
                : Translation.tr("%1 errors").arg(errs.errors.length + errs.hidden)

            function check() {
                if (!errs.hyprland) {
                    errs.status = "unavailable";
                    return;
                }
                if (errorsProc.running)
                    return;
                errs.status = "checking";
                errorsProc.running = true;
            }

            spacing: 8
            Component.onCompleted: errs.check()

            Connections {
                target: advancedPage
                function onVisibleChanged() {
                    if (advancedPage.visible)
                        errs.check();
                }
            }

            Process {
                id: errorsProc
                command: ["hyprctl", "-j", "configerrors"]
                stdout: StdioCollector { id: errorsOut }
                onExited: (exitCode, exitStatus) => {
                    const parsed = exitCode === 0 ? AdvancedLogic.parseConfigErrors(errorsOut.text) : { ok: false, errors: [], hidden: 0 };
                    if (!parsed.ok)
                        console.info(`[AdvancedPage] unexpected hyprctl -j configerrors answer (exit ${exitCode})`);
                    errs.errors = parsed.errors;
                    errs.hidden = parsed.hidden;
                    errs.status = !parsed.ok ? "failed" : parsed.errors.length > 0 ? "errors" : "none";
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                MaterialSymbol {
                    text: errs.status === "none" ? "check_circle" : errs.status === "errors" || errs.status === "failed" ? "error" : "info"
                    iconSize: 20
                    color: errs.status === "errors" || errs.status === "failed" ? Appearance.colors.colError
                        : errs.status === "none" ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                }

                StyledText {
                    objectName: "configErrorsSummary"
                    Layout.fillWidth: true
                    text: errs.summary
                    wrapMode: Text.Wrap
                    color: Appearance.colors.colOnLayer1
                }

                SettingsButton {
                    objectName: "configErrorsCheck"
                    visible: errs.hyprland
                    kind: "tonal"
                    iconName: "refresh"
                    text: Translation.tr("Check again")
                    enabled: !errorsProc.running
                    onClicked: errs.check()
                }
            }

            Rectangle {
                visible: errs.status === "errors"
                Layout.fillWidth: true
                implicitHeight: errorsText.implicitHeight + 20
                radius: SettingsMetrics.controlRadius
                color: Appearance.colors.colLayer2

                TextEdit {
                    id: errorsText
                    objectName: "configErrorsText"
                    anchors {
                        left: parent.left
                        right: parent.right
                        verticalCenter: parent.verticalCenter
                        leftMargin: 12
                        rightMargin: 12
                    }
                    readOnly: true
                    selectByMouse: true
                    textFormat: TextEdit.PlainText
                    wrapMode: TextEdit.WrapAtWordBoundaryOrAnywhere
                    text: errs.errors.join("\n")
                    font.family: Appearance.font.family.monospace
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colOnLayer2
                    selectionColor: Appearance.colors.colPrimary
                    selectedTextColor: Appearance.colors.colOnPrimary
                    Accessible.role: Accessible.StaticText
                    Accessible.name: Translation.tr("Hyprland configuration errors")
                }
            }

            StyledText {
                visible: errs.status === "errors" && errs.hidden > 0
                Layout.fillWidth: true
                text: Translation.tr("%1 more not shown; run hyprctl configerrors to see them all.").arg(errs.hidden)
                wrapMode: Text.Wrap
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
        }
    }

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
