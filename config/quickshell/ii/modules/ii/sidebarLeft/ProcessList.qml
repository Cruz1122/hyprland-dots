pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick
import Quickshell
import Quickshell.Io

// Heaviest processes, refreshed while `active`. Own processes can be ended
// (SIGTERM) with a two-click confirmation.
Rectangle {
    id: root
    property bool active: false
    property bool sortByMemory: false
    property int maxRows: 14
    // [{ pid, user, name, cpu (top-style %, 100 = one core), memory (MiB) }]
    property var rows: []
    property bool primed: false
    property int armedPid: -1
    readonly property string currentUser: Quickshell.env("USER") ?? ""
    readonly property real peak: rows.reduce((max, row) => Math.max(max, root.sortByMemory ? row.memory : row.cpu), 1)

    radius: Appearance.rounding.normal
    color: Appearance.colors.colLayer1
    clip: true

    function toMebibytes(field) {
        const match = field.match(/^([\d.]+)([kmgt]?)$/i);
        if (!match)
            return 0;
        const scale = { "": 1 / 1024, "k": 1 / 1024, "m": 1, "g": 1024, "t": 1024 * 1024 };
        return Number(match[1]) * scale[match[2].toLowerCase()];
    }
    function formatMemory(mebibytes) {
        return mebibytes >= 1024 ? `${(mebibytes / 1024).toFixed(1)} GB` : `${Math.round(mebibytes)} MB`;
    }
    function parse(text) {
        // The first iteration of `top` reports averages since boot; only the
        // last one reflects the sampling window.
        const block = text.split(/^top - /m).pop();
        const parsed = [];
        for (const line of block.split("\n")) {
            const match = line.match(/^\s*(\d+)\s+(\S+)\s+\S+\s+\S+\s+\S+\s+(\S+)\s+\S+\s+\S\s+([\d.]+)\s+[\d.]+\s+\S+\s+(.+)$/);
            if (!match || match[5].trim() === "top")
                continue;
            parsed.push({
                pid: Number(match[1]),
                user: match[2],
                memory: root.toMebibytes(match[3]),
                cpu: Number(match[4]),
                name: match[5].trim()
            });
            if (parsed.length >= root.maxRows)
                break;
        }
        return parsed;
    }
    function endProcess(pid) {
        if (root.armedPid !== pid) {
            root.armedPid = pid;
            disarmTimer.restart();
            return;
        }
        root.armedPid = -1;
        Quickshell.execDetached(["kill", String(pid)]);
    }

    onActiveChanged: {
        if (active && !sampler.running)
            sampler.running = true;
        if (!active)
            armedPid = -1;
    }
    onSortByMemoryChanged: primed = false

    Timer {
        id: disarmTimer
        interval: 2500
        onTriggered: root.armedPid = -1
    }

    Process {
        id: sampler
        environment: ({
            LANG: "C",
            LC_ALL: "C"
        })
        // A short first window so the list is not empty for long, then 2 s.
        command: ["top", "-b", "-d", root.primed ? "2" : "0.5", "-n", "2", "-o", root.sortByMemory ? "%MEM" : "%CPU", "-e", "m", "-w", "200"]
        stdout: StdioCollector {
            onStreamFinished: {
                const parsed = root.parse(text);
                if (parsed.length > 0) {
                    root.rows = parsed;
                    root.primed = true;
                }
            }
        }
        onExited: {
            if (root.active)
                restartTimer.restart();
        }
    }
    Timer { // Lets the command binding settle and bounds the rate if `top` fails
        id: restartTimer
        interval: 200
        onTriggered: if (root.active) sampler.running = true
    }

    Item {
        id: header
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            margins: 8
            leftMargin: 14
        }
        height: 32

        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            text: Translation.tr("Processes")
            font.pixelSize: Appearance.font.pixelSize.normal
            color: Appearance.colors.colOnLayer1
        }

        Row {
            anchors {
                right: parent.right
                verticalCenter: parent.verticalCenter
            }
            spacing: 4
            Repeater {
                model: [
                    { label: "CPU", memory: false },
                    { label: "RAM", memory: true }
                ]
                RippleButton {
                    id: sortButton
                    required property var modelData
                    implicitWidth: 52
                    implicitHeight: 28
                    buttonRadius: height / 2
                    toggled: root.sortByMemory === modelData.memory
                    colBackground: Appearance.colors.colLayer2
                    onClicked: root.sortByMemory = modelData.memory
                    contentItem: StyledText {
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: sortButton.modelData.label
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: sortButton.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1
                    }
                }
            }
        }
    }

    StyledText {
        anchors.centerIn: parent
        visible: root.rows.length === 0
        text: Translation.tr("Measuring…")
        color: Appearance.colors.colSubtext
    }

    ListView {
        id: list
        anchors {
            left: parent.left
            right: parent.right
            top: header.bottom
            bottom: parent.bottom
            margins: 8
            topMargin: 4
        }
        clip: true
        interactive: contentHeight > height
        boundsBehavior: Flickable.StopAtBounds
        spacing: 2
        model: ScriptModel {
            values: root.rows
            objectProp: "pid"
        }

        delegate: Item {
            id: row
            required property var modelData
            readonly property bool own: modelData.user === root.currentUser
            readonly property bool armed: root.armedPid === modelData.pid
            readonly property real share: (root.sortByMemory ? modelData.memory : modelData.cpu) / root.peak
            width: list.width
            height: 34

            HoverHandler {
                id: hover
            }

            Rectangle { // Load bar behind the row
                anchors {
                    left: parent.left
                    top: parent.top
                    bottom: parent.bottom
                }
                width: parent.width * Math.max(0, Math.min(1, row.share))
                radius: Appearance.rounding.verysmall
                color: ColorUtils.transparentize(row.armed ? Appearance.colors.colError : Appearance.colors.colPrimary, 0.86)
                Behavior on width {
                    animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                }
            }

            StyledText {
                anchors {
                    left: parent.left
                    leftMargin: 8
                    right: cpuText.left
                    rightMargin: 8
                    verticalCenter: parent.verticalCenter
                }
                elide: Text.ElideRight
                text: row.armed ? Translation.tr("Click again to end") : row.modelData.name
                font.pixelSize: Appearance.font.pixelSize.small
                color: row.armed ? Appearance.colors.colError : Appearance.colors.colOnLayer1
            }
            StyledText {
                id: cpuText
                anchors {
                    right: memoryText.left
                    verticalCenter: parent.verticalCenter
                }
                width: 54
                horizontalAlignment: Text.AlignRight
                text: `${row.modelData.cpu.toFixed(row.modelData.cpu < 10 ? 1 : 0)}%`
                font.family: Appearance.font.family.numbers
                font.pixelSize: Appearance.font.pixelSize.small
                color: root.sortByMemory ? Appearance.colors.colSubtext : Appearance.colors.colOnLayer1
            }
            StyledText {
                id: memoryText
                anchors {
                    right: endButton.left
                    rightMargin: 4
                    verticalCenter: parent.verticalCenter
                }
                width: 72
                horizontalAlignment: Text.AlignRight
                text: root.formatMemory(row.modelData.memory)
                font.family: Appearance.font.family.numbers
                font.pixelSize: Appearance.font.pixelSize.small
                color: root.sortByMemory ? Appearance.colors.colOnLayer1 : Appearance.colors.colSubtext
            }
            RippleButton {
                id: endButton
                anchors {
                    right: parent.right
                    rightMargin: 2
                    verticalCenter: parent.verticalCenter
                }
                implicitWidth: 28
                implicitHeight: 28
                buttonRadius: height / 2
                enabled: row.own
                opacity: row.own && (hover.hovered || row.armed) ? 1 : 0
                onClicked: root.endProcess(row.modelData.pid)
                contentItem: MaterialSymbol {
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: "close"
                    iconSize: 18
                    color: row.armed ? Appearance.colors.colError : Appearance.colors.colOnLayer1
                }
            }
        }
    }
}
