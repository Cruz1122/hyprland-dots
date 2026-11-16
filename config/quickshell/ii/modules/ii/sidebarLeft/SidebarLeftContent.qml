import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower

Item {
    id: root
    // SideRail hosting this content; drives the staggered entrance.
    property var rail: null
    property int sidebarPadding: 12
    anchors.fill: parent

    Timer {
        id: actionTimer
        property var triggerAction: null
        interval: 300
        repeat: false
        onTriggered: if (triggerAction) triggerAction()
    }

    function delayedAction(action) {
        GlobalStates.sidebarLeftOpen = false;
        actionTimer.triggerAction = action;
        actionTimer.restart();
    }

    // Root filesystem usage in GB.
    property real diskUsed: 0
    property real diskTotal: 0
    property bool recording: false
    readonly property bool live: GlobalStates.sidebarLeftOpen

    Process {
        id: diskProc
        environment: ({ LANG: "C", LC_ALL: "C" })
        command: ["df", "-k", "--output=used,size", "/"]
        stdout: StdioCollector {
            onStreamFinished: {
                const fields = text.trim().split("\n").pop().trim().split(/\s+/).map(Number);
                if (fields.length >= 2 && fields.every(Number.isFinite)) {
                    root.diskUsed = fields[0] / (1024 * 1024);
                    root.diskTotal = fields[1] / (1024 * 1024);
                }
            }
        }
    }
    Process {
        id: recordingProc
        command: ["pidof", "wf-recorder"]
        onExited: exitCode => root.recording = exitCode === 0
    }
    Timer {
        interval: 2000
        running: root.live
        repeat: true
        triggeredOnStart: true
        property int ticks: 0
        onTriggered: {
            if (!recordingProc.running)
                recordingProc.running = true;
            // Disk usage moves slowly: every 30 s is plenty.
            if (ticks % 15 === 0 && !diskProc.running)
                diskProc.running = true;
            ticks += 1;
        }
    }

    function stage(index) {
        return root.rail ? root.rail.stage(index) : 1;
    }
    function stageOffset(index) {
        return root.rail ? root.rail.stageOffset(index) : 0;
    }

    function screenshot() {
        root.delayedAction(() => Quickshell.execDetached([
            "qs", "-p", Quickshell.shellPath(""), "ipc", "call", "region", "screenshot"
        ]));
    }

    function startRecording() {
        const action = Config.options.screenRecord.barButtonAction ?? "fullscreen";
        if (action === "region") {
            const regionAction = Config.options.screenRecord.recordAudioByDefault ? "recordWithSound" : "record";
            Quickshell.execDetached(["qs", "-p", Quickshell.shellPath(""), "ipc", "call", "region", regionAction]);
        } else if (action === "pause") {
            Quickshell.execDetached([Directories.recordScriptPath, "--pause"]);
        } else if (action === "stop") {
            Quickshell.execDetached([Directories.recordScriptPath, "--stop"]);
        } else {
            const command = [Directories.recordScriptPath, "--fullscreen"];
            if (Config.options.screenRecord.recordAudioByDefault) {
                const source = Config.options.screenRecord.audioSource ?? "system";
                if (source === "system") command.push("--sound");
                else if (source === "mic") command.push("--mic");
                else if (source === "both") {
                    command.push("--sound");
                    command.push("--mic");
                }
            }
            Quickshell.execDetached(command);
        }
    }

    function cyclePowerProfile() {
        if (PowerProfiles.hasPerformanceProfile) {
            switch (PowerProfiles.profile) {
            case PowerProfile.PowerSaver: PowerProfiles.profile = PowerProfile.Balanced; break;
            case PowerProfile.Balanced: PowerProfiles.profile = PowerProfile.Performance; break;
            case PowerProfile.Performance: PowerProfiles.profile = PowerProfile.PowerSaver; break;
            }
        } else {
            PowerProfiles.profile = PowerProfiles.profile === PowerProfile.Balanced
                ? PowerProfile.PowerSaver : PowerProfile.Balanced;
        }
    }

    function powerProfileName() {
        switch (PowerProfiles.profile) {
        case PowerProfile.PowerSaver: return Translation.tr("Power Saver");
        case PowerProfile.Performance: return Translation.tr("Performance");
        default: return Translation.tr("Balanced");
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: root.sidebarPadding
        anchors.bottomMargin: 14
        spacing: 10

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            opacity: root.stage(0)
            transform: Translate { x: root.stageOffset(0) }

            ActionTile {
                iconName: "delete_forever"
                label: Translation.tr("End task")
                tooltip: Translation.tr("Task killer")
                triggerAction: () => root.delayedAction(() => Quickshell.execDetached(["qs", "-p", Quickshell.shellPath("taskKiller.qml")]))
            }
            ActionTile {
                iconName: "screenshot_region"
                label: Translation.tr("Capture")
                tooltip: Translation.tr("Screenshot")
                triggerAction: root.screenshot
            }
            ActionTile {
                iconName: root.recording ? "stop_circle" : "videocam"
                label: root.recording ? Translation.tr("Recording") : Translation.tr("Record")
                tooltip: Translation.tr("Screen record")
                alert: root.recording
                triggerAction: () => root.delayedAction(root.startRecording)
            }
            ActionTile {
                iconName: "colorize"
                label: Translation.tr("Color")
                tooltip: Translation.tr("Color picker")
                triggerAction: () => root.delayedAction(() => Quickshell.execDetached(["hyprpicker", "-a"]))
            }
            ActionTile {
                iconName: PowerProfiles.profile === PowerProfile.PowerSaver ? "energy_savings_leaf"
                    : PowerProfiles.profile === PowerProfile.Performance ? "local_fire_department" : "airwave"
                // Short names: the full ones do not fit a tile.
                label: PowerProfiles.profile === PowerProfile.PowerSaver ? Translation.tr("Saver")
                    : PowerProfiles.profile === PowerProfile.Performance ? Translation.tr("Boost") : Translation.tr("Balance")
                tooltip: `${Translation.tr("Power mode")}\n${root.powerProfileName()}`
                active: PowerProfiles.profile === PowerProfile.PowerSaver
                iridescent: PowerProfiles.profile === PowerProfile.Performance
                triggerAction: root.cyclePowerProfile
            }
        }

        SystemCard {
            Layout.fillWidth: true
            opacity: root.stage(1)
            transform: Translate { x: root.stageOffset(1) }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            opacity: root.stage(2)
            transform: Translate { x: root.stageOffset(2) }

            UsageChip {
                visible: ResourceUsage.swapTotal > 1
                icon: "swap_horiz"
                title: Translation.tr("Swap")
                used: ResourceUsage.swapUsed / (1024 * 1024)
                total: ResourceUsage.swapTotal / (1024 * 1024)
            }
            UsageChip {
                icon: "hard_drive"
                title: Translation.tr("Disk")
                used: root.diskUsed
                total: root.diskTotal
            }
        }

        ProcessList {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 120
            active: root.live
            opacity: root.stage(3)
            transform: Translate { x: root.stageOffset(3) }
        }
    }
}
