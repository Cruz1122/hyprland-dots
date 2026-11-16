pragma Singleton
import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell

// Icon for a window. Terminal windows show the TUI program running inside
// them (recognised from the window title) with the terminal as a badge.
Singleton {
    id: root

    // TUI programs recognised from a terminal window's title. `icon` names a
    // monochrome mask in assets/icons/ai. Claude Code titles carry no app
    // name, only its status glyph ("✳ topic", or a rotating "◐" while busy).
    readonly property var titleApps: [
        { icon: "claude", pattern: /^[✳◐◑◒◓]\s|\bclaude\b/i },
        { icon: "openai", pattern: /\bcodex\b/i },
        { icon: "cursor", pattern: /\bcursor[- ]agent\b/i },
        { icon: "opencode", pattern: /\bopencode\b/i },
    ]

    // Icon files for names the icon theme fails to resolve.
    // Workaround: the long-running shell has been seen unable to resolve
    // "kitty" from the theme while a fresh process resolves it fine.
    readonly property var iconFiles: ({
        "kitty": "/usr/share/icons/hicolor/scalable/apps/kitty.svg",
    })

    function themedSource(name) {
        const themed = Quickshell.iconPath(name, true);
        if (themed.length > 0)
            return themed;
        const file = root.iconFiles[name];
        return file ? `file://${file}` : Quickshell.iconPath("image-missing");
    }

    function isTerminal(windowClass) {
        return NotificationUtils.terminalNames.includes(String(windowClass ?? "").toLowerCase());
    }

    // -> { source, isMask, badge }: `isMask` marks a monochrome image to be
    // tinted; `badge` is the hosting terminal's icon source, or "".
    function describe(windowClass, title) {
        const className = String(windowClass ?? "");
        if (!root.isTerminal(className)) {
            return {
                source: Quickshell.iconPath(AppSearch.guessIcon(className), "image-missing"),
                isMask: false,
                badge: "",
            };
        }

        const terminalSource = root.themedSource(className.toLowerCase());
        const text = String(title ?? "").trim();
        const app = root.titleApps.find(candidate => candidate.pattern.test(text));
        if (app) {
            return {
                source: Qt.resolvedUrl(`${Directories.assetsPath}/icons/ai/${app.icon}.svg`).toString(),
                isMask: true,
                badge: terminalSource,
            };
        }

        // "btop", "nvim notes.md", ...: the leading word, when it is exactly an
        // installed icon's name. No fuzzy guessing, which would match prose.
        const firstWord = text.split(/\s+/)[0].toLowerCase();
        if (/^[a-z0-9][a-z0-9._+-]{1,23}$/.test(firstWord) && !root.isTerminal(firstWord) && AppSearch.iconExists(firstWord)) {
            return {
                source: Quickshell.iconPath(firstWord),
                isMask: false,
                badge: terminalSource,
            };
        }

        return { source: terminalSource, isMask: false, badge: "" };
    }
}
