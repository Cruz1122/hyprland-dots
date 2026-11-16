pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import QtQuick
import "PosterBank.js" as Bank

// Posters for empty workspaces: the date, a very large symbol and a topic
// with its one-line hook. Every workspace gets its own topic; the deal is
// reshuffled daily. Fill the background window with it.
Item {
    id: root
    required property int workspaceId
    // This screen is one an audience watches: it shows the holding message
    // instead of a topic.
    property bool presenting: false
    // The feature is on and the desktop is visible.
    property bool shown: true

    // Changes at midnight; the shuffles only depend on it.
    readonly property int daySeed: {
        const date = DateTime.clock.date;
        return date.getFullYear() * 10000 + (date.getMonth() + 1) * 100 + date.getDate();
    }
    readonly property var plan: Bank.plan(daySeed)

    // Read by the pages.
    readonly property bool iridescent: GlobalStates.iridescent
    readonly property string weekdayText: capitalized(Qt.locale().toString(DateTime.clock.date, "dddd"))
    // Spanish wants "12 de noviembre"; the generic form reads fine elsewhere.
    readonly property string dayMonthText: Qt.locale().toString(DateTime.clock.date, Qt.locale().name.startsWith("es") ? "d 'de' MMMM" : "d MMMM")
    readonly property string dateText: `${weekdayText}, ${dayMonthText}`

    function capitalized(text) {
        return text.charAt(0).toUpperCase() + text.slice(1);
    }

    readonly property var occupiedWorkspaces: {
        const occupied = {};
        for (const win of HyprlandData.windowList) {
            const id = win?.workspace?.id;
            if (id !== undefined)
                occupied[id] = true;
        }
        return occupied;
    }
    function isEmpty(id) {
        return occupiedWorkspaces[id] !== true;
    }

    visible: shown

    // Swapped in place on a workspace switch: the poster does not travel with
    // the windows.
    PosterPage {
        host: root
        anchors.fill: parent
        workspaceId: root.workspaceId
        visible: root.isEmpty(workspaceId)
    }
}
