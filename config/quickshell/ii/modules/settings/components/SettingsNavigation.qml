import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs.modules.settings.core

// Grouped page list with global search. Collapses to icons when the window
// is narrower than SettingsMetrics.navAutoCollapseWidth; the menu button
// overrides that until the window crosses the threshold again.
ColumnLayout {
    id: root

    property string currentPageId: ""
    property real windowWidth: 1100
    readonly property bool autoExpanded: root.windowWidth >= SettingsMetrics.navAutoCollapseWidth
    // null follows autoExpanded; true/false is the user's choice.
    property var userExpanded: null
    property bool searchOpen: false
    readonly property bool expanded: root.searchOpen || (root.userExpanded ?? root.autoExpanded)
    readonly property string query: searchField.text
    readonly property var results: root.query.trim().length > 0 ? SettingsRegistry.search(root.query, 30) : []
    property int resultIndex: 0

    signal pageSelected(string pageId)
    signal resultActivated(var result)

    objectName: "settingsNavigation"
    spacing: 6
    clip: true
    Layout.fillHeight: true
    Layout.preferredWidth: root.expanded ? SettingsMetrics.navExpandedWidth : SettingsMetrics.navCollapsedWidth
    Layout.minimumWidth: Layout.preferredWidth
    Layout.maximumWidth: Layout.preferredWidth

    Behavior on Layout.preferredWidth {
        NumberAnimation {
            duration: SettingsMetrics.transitionDuration
            easing.type: Easing.OutCubic
        }
    }

    onAutoExpandedChanged: root.userExpanded = null
    onCurrentPageIdChanged: Qt.callLater(root.revealCurrent)

    // Scrolls the page list so the selected page is visible.
    function revealCurrent() {
        const find = item => {
            if (item.objectName === "nav:" + root.currentPageId)
                return item;
            for (const child of item.children) {
                const found = find(child);
                if (found)
                    return found;
            }
            return null;
        };
        const item = find(groupsColumn);
        if (!item)
            return;
        // Keep the item clear of the edge fades. The first page of a group
        // brings its group title into view as well.
        const fade = SettingsMetrics.navEdgeFadeHeight;
        const group = item.parent;
        const firstInGroup = Array.from(group?.children ?? []).find(c => String(c.objectName).startsWith("nav:")) === item;
        const y = item.mapToItem(groupsColumn, 0, 0).y;
        const top = firstInGroup ? group.mapToItem(groupsColumn, 0, 0).y : y - fade;
        if (top < pagesView.contentY)
            pagesView.contentY = Math.max(0, top);
        else if (y + item.height > pagesView.contentY + pagesView.height)
            pagesView.contentY = Math.min(pagesView.contentHeight - pagesView.height, y + item.height - pagesView.height + fade);
    }
    onResultsChanged: root.resultIndex = 0

    function focusSearch() {
        root.searchOpen = true;
        Qt.callLater(() => searchField.forceActiveFocus());
    }

    function setQuery(text) {
        root.searchOpen = true;
        searchField.text = text;
    }

    function clearSearch() {
        searchField.text = "";
        searchField.focus = false;
        root.searchOpen = false;
    }

    function activateResult(index) {
        const result = root.results[index];
        if (!result)
            return;
        root.clearSearch();
        root.resultActivated(result);
    }

    function resultLabel(result) {
        if (result.kind === "entry")
            return Translation.tr(SettingsRegistry.entry(result.key)?.label ?? result.key);
        if (result.kind === "section")
            return Translation.tr(SettingsRegistry.section(result.pageId, result.sectionId)?.title ?? "");
        return Translation.tr(SettingsRegistry.page(result.pageId)?.title ?? "");
    }

    function resultContext(result) {
        const page = Translation.tr(SettingsRegistry.page(result.pageId)?.title ?? "");
        if (result.kind === "entry") {
            const section = SettingsRegistry.section(result.pageId, result.sectionId);
            return section ? `${page} › ${Translation.tr(section.title)}` : page;
        }
        if (result.kind === "section")
            return page;
        return Translation.tr("Page");
    }

    // Shades the edge of a scrolled list where more items continue, so they
    // fade out instead of looking cut off at the search field or the footer.
    component EdgeFade: Rectangle {
        required property Flickable view
        property bool atTop: false

        parent: view
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: atTop ? parent.top : undefined
        anchors.bottom: atTop ? undefined : parent.bottom
        implicitHeight: SettingsMetrics.navEdgeFadeHeight
        visible: atTop ? !view.atYBeginning : !view.atYEnd
        gradient: Gradient {
            GradientStop { position: 0; color: atTop ? Appearance.m3colors.m3background : "transparent" }
            GradientStop { position: 1; color: atTop ? "transparent" : Appearance.m3colors.m3background }
        }
    }

    // Menu button and search
    GridLayout {
        Layout.fillWidth: true
        Layout.leftMargin: root.expanded ? 4 : 0
        columns: root.expanded ? 2 : 1
        columnSpacing: 6
        rowSpacing: 6

        SettingsIconButton {
            Layout.alignment: Qt.AlignHCenter
            iconName: root.expanded ? "menu_open" : "menu"
            tooltip: root.expanded ? Translation.tr("Collapse navigation") : Translation.tr("Expand navigation")
            size: 44
            iconSize: 22
            onClicked: {
                root.searchOpen = false;
                root.userExpanded = !root.expanded;
            }
        }

        SettingsIconButton {
            visible: !root.expanded
            Layout.alignment: Qt.AlignHCenter
            iconName: "search"
            tooltip: Translation.tr("Search settings")
            size: 44
            iconSize: 22
            onClicked: root.focusSearch()
        }

        SettingsTextField {
            id: searchField
            objectName: "settingsSearchField"
            visible: root.expanded
            Layout.fillWidth: true
            leftPadding: 40
            rightPadding: clearButton.visible ? 40 : 14
            placeholderText: Translation.tr("Search settings")
            Accessible.name: Translation.tr("Search settings")
            Accessible.role: Accessible.EditableText

            onActiveFocusChanged: {
                if (!searchField.activeFocus && searchField.text.length === 0)
                    root.searchOpen = false;
            }
            Keys.onDownPressed: root.resultIndex = Math.min(root.resultIndex + 1, root.results.length - 1)
            Keys.onUpPressed: root.resultIndex = Math.max(root.resultIndex - 1, 0)
            Keys.onReturnPressed: root.activateResult(root.resultIndex)
            Keys.onEnterPressed: root.activateResult(root.resultIndex)
            Keys.onEscapePressed: root.clearSearch()

            MaterialSymbol {
                anchors.left: parent.left
                anchors.leftMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                text: "search"
                iconSize: 20
                color: Appearance.colors.colSubtext
            }

            SettingsIconButton {
                id: clearButton
                visible: searchField.text.length > 0
                anchors.right: parent.right
                anchors.rightMargin: 4
                anchors.verticalCenter: parent.verticalCenter
                iconName: "close"
                tooltip: Translation.tr("Clear search")
                size: 30
                iconSize: 18
                onClicked: root.clearSearch()
            }
        }
    }

    // Search results
    ListView {
        id: resultsView
        objectName: "settingsSearchResults"
        visible: root.query.trim().length > 0 && root.expanded
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.topMargin: 4
        clip: true
        spacing: 2
        model: root.results
        currentIndex: root.resultIndex
        boundsBehavior: Flickable.StopAtBounds

        delegate: RippleButton {
            id: resultItem
            required property var modelData
            required property int index
            readonly property bool current: resultItem.index === root.resultIndex

            width: ListView.view.width // size-ok: list delegates follow the view width
            implicitHeight: resultLayout.implicitHeight + 16
            buttonRadius: SettingsMetrics.rowRadius
            toggled: resultItem.current
            colBackground: "transparent"
            colBackgroundHover: Appearance.colors.colLayer1Hover
            colBackgroundToggled: Appearance.colors.colSecondaryContainer
            colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
            colRippleToggled: Appearance.colors.colSecondaryContainerActive
            focusPolicy: Qt.NoFocus
            Accessible.name: `${root.resultLabel(resultItem.modelData)}, ${root.resultContext(resultItem.modelData)}`
            onClicked: root.activateResult(resultItem.index)

            contentItem: Item {
                implicitHeight: resultLayout.implicitHeight

                ColumnLayout {
                    id: resultLayout
                    anchors {
                        left: parent.left
                        right: parent.right
                        verticalCenter: parent.verticalCenter
                        leftMargin: 4
                        rightMargin: 4
                    }
                    spacing: 1

                    StyledText {
                        Layout.fillWidth: true
                        text: root.resultLabel(resultItem.modelData)
                        elide: Text.ElideRight
                        color: resultItem.current ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: root.resultContext(resultItem.modelData)
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: resultItem.current ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colSubtext
                    }
                }
            }
        }

        EdgeFade {
            view: resultsView
            atTop: true
        }

        EdgeFade {
            view: resultsView
        }

        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 16
            visible: root.results.length === 0
            text: Translation.tr("No results")
            color: Appearance.colors.colSubtext
        }
    }

    // Page groups
    Flickable {
        id: pagesView
        objectName: "settingsPageList"
        visible: !resultsView.visible
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        contentHeight: groupsColumn.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: StyledScrollBar {}

        EdgeFade {
            view: pagesView
            atTop: true
        }

        EdgeFade {
            view: pagesView
        }

        ColumnLayout {
            id: groupsColumn
            width: pagesView.width // size-ok: content column of the flickable follows the viewport
            spacing: 2

            Repeater {
                model: SettingsRegistry.groups

                delegate: ColumnLayout {
                    id: group
                    required property var modelData
                    required property int index
                    Layout.fillWidth: true
                    spacing: 2

                    StyledText {
                        visible: root.expanded
                        Layout.fillWidth: true
                        Layout.leftMargin: 18
                        Layout.topMargin: group.index === 0 ? 4 : 12
                        Layout.bottomMargin: 4
                        text: Translation.tr(group.modelData.title)
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.Medium
                        color: Appearance.colors.colSubtext
                        Accessible.role: Accessible.Heading
                    }

                    Rectangle {
                        visible: !root.expanded && group.index > 0
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: 6
                        Layout.bottomMargin: 6
                        implicitWidth: 24
                        implicitHeight: 1
                        color: Appearance.colors.colOutlineVariant
                    }

                    Repeater {
                        model: group.modelData.pages

                        delegate: SettingsNavigationItem {
                            required property var modelData
                            Layout.fillWidth: root.expanded
                            Layout.alignment: Qt.AlignHCenter
                            page: modelData
                            expanded: root.expanded
                            selected: root.currentPageId === modelData.id
                            onClicked: root.pageSelected(modelData.id)
                        }
                    }
                }
            }
        }
    }

    Rectangle {
        Layout.fillWidth: true
        Layout.leftMargin: 12
        Layout.rightMargin: 12
        Layout.topMargin: 4
        Layout.bottomMargin: 4
        implicitHeight: 1
        color: Appearance.colors.colOutlineVariant
    }

    Repeater {
        model: SettingsRegistry.footerPages

        delegate: SettingsNavigationItem {
            required property var modelData
            Layout.fillWidth: root.expanded
            Layout.alignment: Qt.AlignHCenter
            page: modelData
            expanded: root.expanded
            selected: root.currentPageId === modelData.id
            onClicked: root.pageSelected(modelData.id)
        }
    }
}
