pragma Singleton

import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Wayland

Singleton {
    id: root

    // Window classes are matched lowercased, pinned ids keep the spelling they
    // were pinned with (desktop entry ids such as "org.kde.dolphin").
    function isPinned(appId) {
        const id = String(appId ?? "").toLowerCase();
        return (Config.options?.dock.pinnedApps ?? []).some(pinned => pinned.toLowerCase() === id);
    }

    function togglePin(appId) {
        const id = String(appId ?? "").toLowerCase();
        const pinnedApps = Config.options.dock.pinnedApps;
        if (root.isPinned(id))
            Config.options.dock.pinnedApps = pinnedApps.filter(pinned => pinned.toLowerCase() !== id);
        else
            Config.options.dock.pinnedApps = pinnedApps.concat([appId]);
    }

    // One entry per app id; terminal windows stay under their terminal.
    readonly property list<var> apps: root.buildEntries(false)
    // Same, but a terminal window running a recognised TUI program (Claude
    // Code, btop, ...) gets its own entry, like the launcher panel's icons.
    readonly property list<var> dockApps: root.buildEntries(true)

    // Entries are reused across rebuilds (stable identity keeps delegates and
    // avoids leaking one object per window change). Mutated, never reassigned,
    // so the bindings above do not depend on it.
    property var entryCache: ({})
    property var retiredEntries: []

    function sameItems(a, b) {
        if (a.length !== b.length)
            return false;
        for (let i = 0; i < a.length; ++i) {
            if (a[i] !== b[i])
                return false;
        }
        return true;
    }

    // Last path segment of the icon source, without extension: "claude", "btop".
    function programId(source) {
        return String(source).split("/").pop().replace(/\.(svg|png)$/, "");
    }

    function buildEntries(splitPrograms) {
        const groups = new Map();
        const group = (key, fields) => {
            if (!groups.has(key))
                groups.set(key, Object.assign({ program: "", pinned: false, toplevels: [] }, fields));
            return groups.get(key);
        };

        const pinnedApps = Config.options?.dock.pinnedApps ?? [];
        for (const appId of pinnedApps)
            group(appId.toLowerCase(), { windowClass: appId, pinned: true });

        const ignoredRegexes = (Config.options?.dock.ignoredAppRegexes ?? []).map(pattern => new RegExp(pattern, "i"));
        const running = [];
        for (const toplevel of ToplevelManager.toplevels.values) {
            const windowClass = String(toplevel.appId ?? "");
            if (ignoredRegexes.some(re => re.test(windowClass)))
                continue;
            let key = windowClass.toLowerCase();
            let program = "";
            if (splitPrograms && WindowIcons.isTerminal(windowClass)) {
                const info = WindowIcons.describe(windowClass, toplevel.title);
                if (info.badge.length > 0) {
                    program = root.programId(info.source);
                    key = `${key}::${program}`;
                }
            }
            const entry = group(key, { windowClass: windowClass, program: program });
            if (!entry.pinned && entry.toplevels.length === 0)
                running.push(key);
            entry.toplevels.push(toplevel);
        }

        const keys = pinnedApps.map(appId => appId.toLowerCase()).filter((key, index, all) => all.indexOf(key) === index);
        if (keys.length > 0 && running.length > 0) {
            group("SEPARATOR", { windowClass: "" });
            keys.push("SEPARATOR");
        }
        keys.push(...running);

        const prefix = splitPrograms ? "dock:" : "apps:";
        const live = {};
        const values = [];
        for (const key of keys) {
            const fields = groups.get(key);
            const cacheKey = prefix + key;
            // Plain JS record so reading the shadows below adds no dependency.
            let cached = root.entryCache[cacheKey];
            if (!cached) {
                cached = {
                    entry: appEntryComp.createObject(root, {
                        appId: key,
                        windowClass: fields.windowClass,
                        program: fields.program,
                        toplevels: fields.toplevels,
                        pinned: fields.pinned
                    }),
                    toplevels: fields.toplevels,
                    pinned: fields.pinned
                };
                root.entryCache[cacheKey] = cached;
            } else {
                // Window titles change constantly (Claude Code's busy spinner);
                // only push real changes to the delegates.
                if (!root.sameItems(cached.toplevels, fields.toplevels)) {
                    cached.toplevels = fields.toplevels;
                    cached.entry.toplevels = fields.toplevels;
                }
                if (cached.pinned !== fields.pinned) {
                    cached.pinned = fields.pinned;
                    cached.entry.pinned = fields.pinned;
                }
            }
            live[cacheKey] = true;
            values.push(cached.entry);
        }

        for (const cacheKey of Object.keys(root.entryCache)) {
            if (cacheKey.startsWith(prefix) && !live[cacheKey]) {
                root.retiredEntries.push(root.entryCache[cacheKey].entry);
                delete root.entryCache[cacheKey];
                retireTimer.restart();
            }
        }
        return values;
    }

    // Delegates may still read a removed entry during their remove transition.
    Timer {
        id: retireTimer
        interval: 2000
        onTriggered: {
            // In place: reassigning would re-run the entry bindings.
            const retired = root.retiredEntries.splice(0);
            for (const entry of retired)
                entry.destroy();
        }
    }

    component TaskbarAppEntry: QtObject {
        required property string appId
        // Window class to launch and look up the desktop entry with.
        property string windowClass: appId
        // TUI program id for split terminal entries ("claude", "btop"), else "".
        property string program: ""
        required property list<var> toplevels
        required property bool pinned
    }
    Component {
        id: appEntryComp
        TaskbarAppEntry {}
    }
}
