pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Wayland sessions from /usr/share/wayland-sessions. Hyprland is the default.
Singleton {
    id: root

    property list<var> sessions: []
    property int currentIndex: 0
    readonly property var current: sessions[currentIndex] ?? fallback
    // Used before the directory has been read, or when it is empty.
    readonly property var fallback: ({
        id: "hyprland",
        name: "Hyprland",
        command: ["/usr/bin/start-hyprland"],
        desktopNames: "Hyprland"
    })
    readonly property string defaultId: "hyprland"

    function cycle(step) {
        if (sessions.length > 0)
            currentIndex = (currentIndex + step + sessions.length) % sessions.length;
    }

    // Exec lines of the shipped session files carry no quoting; field codes
    // (%f, %u, ...) are not valid in session entries and are dropped.
    function splitExec(exec) {
        return exec.split(/\s+/).filter(arg => arg.length > 0 && !/^%[a-zA-Z]$/.test(arg));
    }

    Process {
        running: true
        command: ["sh", "-c", "grep -H -E '^(Name|Exec|DesktopNames|NoDisplay|Hidden)=' /usr/share/wayland-sessions/*.desktop"]
        stdout: StdioCollector {
            onStreamFinished: {
                const byFile = {};
                for (const line of text.split("\n")) {
                    const match = line.match(/^(.*\/([^/]+)\.desktop):([A-Za-z]+)=(.*)$/);
                    if (!match)
                        continue;
                    if (!byFile[match[2]])
                        byFile[match[2]] = { id: match[2] };
                    const entry = byFile[match[2]];
                    entry[match[3]] = match[4].trim();
                }
                const list = [];
                for (const entry of Object.values(byFile)) {
                    if (!entry.Exec || entry.NoDisplay === "true" || entry.Hidden === "true")
                        continue;
                    list.push({
                        id: entry.id,
                        name: entry.Name ?? entry.id,
                        command: root.splitExec(entry.Exec),
                        desktopNames: (entry.DesktopNames ?? "").replace(/;$/, "").replace(/;/g, ":")
                    });
                }
                list.sort((a, b) => a.name.localeCompare(b.name));
                root.sessions = list;
                root.currentIndex = Math.max(0, list.findIndex(s => s.id === root.defaultId));
            }
        }
        onExited: (code, status) => {
            if (code !== 0)
                console.warn(`greeter: listing sessions failed (exit ${code}); using ${root.fallback.name}`);
        }
    }
}
