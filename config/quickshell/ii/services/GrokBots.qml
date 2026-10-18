pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

/** Read-only bridge to Grok Bot's local, sanitized roster snapshot. */
Singleton {
    id: root

    readonly property bool available: snapshot.available === true && bots.length > 0
    readonly property list<var> bots: snapshot.bots ?? []
    readonly property list<var> unreadBots: bots.filter(bot => bot.hasUnread === true)
        .sort((a, b) => (Number(b.lastActivityAt) || 0) - (Number(a.lastActivityAt) || 0))
    readonly property int totalUnread: unreadBots.reduce((total, bot) => total + Math.max(0, Number(bot.unreadCount) || 0), 0)
    readonly property var latestUnread: unreadBots.length > 0 ? unreadBots[0] : null
    property var snapshot: ({ available: false, bots: [] })
    property string rosterScript: FileUtils.trimFileProtocol(`${Directories.scriptPath}/grok-roster.py`)
    property string openScript: FileUtils.trimFileProtocol(`${Directories.scriptPath}/grok-open-bot.sh`)

    function botForNotification(notification) {
        if (!notification || notification.appName !== "Grok Bot") return null;
        const summary = String(notification.summary ?? "");
        return bots.find(bot => bot.name === summary) ?? null;
    }

    function openBot(botId) {
        const id = String(botId ?? "");
        if (!/^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$/.test(id)) {
            console.warn("[GrokBots] Refusing invalid bot id");
            return false;
        }
        Quickshell.execDetached([root.openScript, id]);
        return true;
    }

    function refresh() {
        if (!rosterReader.running) rosterReader.running = true;
    }

    Process {
        id: rosterReader
        command: ["python3", root.rosterScript]
        stdout: StdioCollector {
            id: rosterOutput
            onStreamFinished: {
                try {
                    const parsed = JSON.parse(rosterOutput.text);
                    if (parsed && Array.isArray(parsed.bots)) root.snapshot = parsed;
                    else root.snapshot = ({ available: false, bots: [] });
                } catch (error) {
                    console.warn("[GrokBots] Invalid roster snapshot: " + error);
                    root.snapshot = ({ available: false, bots: [] });
                }
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) root.snapshot = ({ available: false, bots: [] });
        }
    }

    Timer {
        interval: 2500
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }
}
