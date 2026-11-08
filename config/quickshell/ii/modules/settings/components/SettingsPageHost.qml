import QtQuick
import Quickshell
import qs.modules.common

// Shows one page at a time. Pages are created on first visit and kept, so
// switching back is instant and keeps the scroll position. The previous page
// stays visible until the next one exists, so there is no blank frame.
Item {
    id: root

    property string currentId: ""
    readonly property Item currentItem: root._current
    // False while the requested page is being created.
    readonly property bool ready: root._current !== null && root._currentId === root.currentId
    property var _cache: ({})
    property Item _current: null
    property string _currentId: ""

    signal pageLoaded(string pageId, Item item)

    // `source` is relative to the shell root (Quickshell.shellPath).
    function setSource(pageId, source) {
        root.currentId = pageId;
        let item = root._cache[pageId] ?? null;
        if (!item) {
            const component = Qt.createComponent(Quickshell.shellPath(source));
            if (component.status !== Component.Ready) {
                console.warn(`[SettingsPageHost] ${source}: ${component.errorString()}`);
                return;
            }
            item = component.createObject(container, { visible: false });
            if (!item) {
                console.warn(`[SettingsPageHost] ${source}: could not create the page`);
                return;
            }
            item.anchors.fill = container;
            root._cache[pageId] = item;
        }
        if (root._current && root._current !== item)
            root._current.visible = false;
        item.opacity = 0;
        item.visible = true;
        root._current = item;
        root._currentId = pageId;
        fadeIn.restart();
        root.pageLoaded(pageId, item);
    }

    Item {
        id: container
        anchors.fill: parent
    }

    NumberAnimation {
        id: fadeIn
        target: root._current
        property: "opacity"
        from: 0
        to: 1
        duration: 160
        easing.type: Easing.OutCubic
    }
}
