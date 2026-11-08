import QtQuick
import Quickshell
import qs.modules.common
import qs.modules.common.functions
import qs.modules.settings.core
import qs.modules.settings.components
import "../backends/IdleLogic.js" as IdleLogic

// Power and lock. The idle actions appear only when the hypridle file and
// config.json disagree; nothing is rewritten on load. They render the stored
// values and restart hypridle; IdleBackend watches the file and hides them.
SettingsPage {
    id: powerPage
    pageId: "power"

    function applyIdle(force) {
        const values = {};
        for (const key of IdleLogic.KEYS)
            values[key] = SettingsStore.value(key);
        if (IdleLogic.orderProblem(values).length > 0)
            return;
        Quickshell.execDetached(IdleLogic.applyArgs(Quickshell.shellPath("scripts/settings/idlegen.py"),
            FileUtils.trimFileProtocol(Directories.home), values, force));
    }

    actions: ({
        applyIdle: entry => powerPage.applyIdle(false),
        replaceIdle: entry => powerPage.applyIdle(true)
    })
}
