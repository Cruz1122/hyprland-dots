import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs.modules.settings.core
import "../core/SettingsLogic.js" as Logic

// Renders a registry page: header, then every section and entry in registry
// order with the row variant chosen by entry.widget.
//
// customDelegates: { entryKey: Component } for `custom` entries.
// actions: { actionName: function(entry) } for `action` entries.
// infoValues: { entryKey: text } shown by `info` entries.
StyledFlickable {
    id: page

    property string pageId: ""
    property var customDelegates: ({})
    property var actions: ({})
    property var infoValues: ({})

    readonly property var pageData: SettingsRegistry.page(page.pageId)
    readonly property var entries: SettingsRegistry.entriesForPage(page.pageId)
    readonly property real margin: page.width < 700 ? SettingsMetrics.compactPageMargin : SettingsMetrics.pageMargin
    readonly property int modifiedCount: {
        void SettingsStore.revision;
        void page.entries;
        return SettingsStore.modifiedCount(page.pageId);
    }
    property bool confirmingReset: false
    readonly property Item focusItem: Window.activeFocusItem

    readonly property var rowSources: ({
        "switch": "SettingsSwitchRow.qml",
        "slider": "SettingsSliderRow.qml",
        "spin": "SettingsSpinRow.qml",
        "segmented": "SettingsSegmentedRow.qml",
        "select": "SettingsSelectRow.qml",
        "text": "SettingsTextRow.qml",
        "textarea": "SettingsTextAreaRow.qml",
        "path": "SettingsPathRow.qml",
        "font": "SettingsFontRow.qml",
        "color": "SettingsColorRow.qml",
        "list": "SettingsListRow.qml",
        "time": "SettingsTimeRow.qml",
        "device": "SettingsDeviceRow.qml",
        "action": "SettingsActionRow.qml",
        "info": "SettingsInfoRow.qml",
        "banner": "SettingsBannerRow.qml",
        "animation": "SettingsAnimationRow.qml",
        "animationPreset": "SettingsAnimationPresetRow.qml",
        "curveLibrary": "SettingsCurveLibraryRow.qml",
        "custom": "SettingsCustomRow.qml"
    })

    clip: true
    contentWidth: page.width
    contentHeight: column.implicitHeight + 2 * page.margin
    Accessible.role: Accessible.Pane
    Accessible.name: Translation.tr(page.pageData?.title ?? "")

    // English reason shown once at the top of a section when every visible,
    // writable row in it is unavailable for that same reason, else "".
    function sectionBannerReason(sectionId) {
        void SettingsStore.revision;
        return Logic.sectionBannerReason(page.entries.filter(e => e.section === sectionId).map(e => {
            const available = SettingsStore.isAvailable(e.key);
            return {
                visible: SettingsStore.isVisible(e.key),
                writable: Logic.isWritable(e),
                available: available,
                reason: available ? "" : SettingsStore.unavailableReason(e.key)
            };
        }));
    }

    function findItem(item, name) {
        if (!item)
            return null;
        if (item.objectName === name)
            return item;
        for (const child of item.children) {
            const found = page.findItem(child, name);
            if (found)
                return found;
        }
        return null;
    }

    function scrollToItem(item) {
        const y = item.mapToItem(page.contentItem, 0, 0).y;
        const target = Math.max(0, Math.min(y - page.height / 3, page.contentHeight - page.height));
        scrollAnimation.to = target;
        scrollAnimation.restart();
    }

    // Reveals and highlights the row of `key`; returns false when the row is
    // not on this page or hidden.
    function scrollTo(key) {
        const row = page.findItem(column, "row:" + key);
        if (!row || !row.visible || !row.parent?.visible)
            return false;
        page.scrollToItem(row);
        row.pulse();
        return true;
    }

    function scrollToSection(sectionId) {
        const section = page.findItem(column, "section:" + sectionId);
        if (!section || !section.visible)
            return false;
        page.scrollToItem(section);
        return true;
    }

    // Keeps the keyboard focus visible while tabbing through the rows.
    onFocusItemChanged: {
        const item = page.focusItem;
        if (!item || scrollAnimation.running)
            return;
        for (let p = item.parent; p; p = p.parent) {
            if (p === column) {
                const y = item.mapToItem(page.contentItem, 0, 0).y;
                if (y < page.contentY + 16)
                    page.contentY = Math.max(0, y - 24);
                else if (y + item.height > page.contentY + page.height - 16)
                    page.contentY = Math.min(page.contentHeight - page.height, y + item.height - page.height + 24);
                return;
            }
        }
    }

    NumberAnimation {
        id: scrollAnimation
        target: page
        property: "contentY"
        duration: 380
        easing.type: Easing.OutCubic
    }

    ColumnLayout {
        id: column
        x: Math.max(page.margin, (page.width - column.width) / 2)
        y: page.margin
        width: Math.min(SettingsMetrics.maxContentWidth, page.width - 2 * page.margin) // size-ok: content column of the flickable follows the viewport
        spacing: SettingsMetrics.sectionSpacing

        // Header
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 14

            RowLayout {
                Layout.fillWidth: true
                spacing: 16

                Rectangle {
                    Layout.alignment: Qt.AlignTop
                    implicitWidth: 52
                    implicitHeight: 52
                    radius: 18
                    color: Appearance.colors.colPrimaryContainer

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: page.pageData?.icon ?? "settings"
                        rotation: page.pageData?.iconRotation ?? 0
                        iconSize: 28
                        color: Appearance.colors.colOnPrimaryContainer
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 4

                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr(page.pageData?.title ?? "")
                        wrapMode: Text.Wrap
                        font.family: Appearance.font.family.title
                        font.variableAxes: Appearance.font.variableAxes.title
                        font.pixelSize: Appearance.font.pixelSize.hugeass + 4
                        color: Appearance.colors.colOnLayer0
                        Accessible.role: Accessible.Heading
                    }

                    StyledText {
                        visible: text.length > 0
                        Layout.fillWidth: true
                        text: Translation.tr(page.pageData?.description ?? "")
                        wrapMode: Text.Wrap
                        color: Appearance.colors.colSubtext
                    }
                }

                SettingsButton {
                    visible: page.modifiedCount > 0 && !page.confirmingReset
                    Layout.alignment: Qt.AlignTop
                    kind: "text"
                    iconName: "restart_alt"
                    text: Translation.tr("Reset page")
                    onClicked: page.confirmingReset = true
                }
            }

            // Inline confirmation for "Reset page".
            Rectangle {
                visible: page.confirmingReset
                Layout.fillWidth: true
                implicitHeight: confirmLayout.implicitHeight + 24
                radius: SettingsMetrics.cardRadius
                color: Appearance.colors.colErrorContainer

                GridLayout {
                    id: confirmLayout
                    anchors {
                        left: parent.left
                        right: parent.right
                        verticalCenter: parent.verticalCenter
                        leftMargin: 18
                        rightMargin: 12
                    }
                    columns: page.width < 640 ? 1 : 2
                    columnSpacing: 12
                    rowSpacing: 8

                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Reset %1 changed settings on this page to their defaults?").arg(page.modifiedCount)
                        wrapMode: Text.Wrap
                        color: Appearance.colors.colOnErrorContainer
                    }

                    RowLayout {
                        Layout.alignment: Qt.AlignRight
                        spacing: 8

                        SettingsButton {
                            kind: "text"
                            text: Translation.tr("Cancel")
                            onClicked: page.confirmingReset = false
                        }

                        SettingsButton {
                            kind: "danger"
                            iconName: "restart_alt"
                            text: Translation.tr("Reset")
                            onClicked: {
                                page.confirmingReset = false;
                                SettingsStore.resetPage(page.pageId);
                            }
                        }
                    }
                }
            }
        }

        Repeater {
            model: SettingsRegistry.sections(page.pageId)

            delegate: SettingsSection {
                id: section
                required property var modelData
                readonly property var sectionEntries: page.entries.filter(e => e.section === section.modelData.id)
                readonly property var sectionKeys: section.sectionEntries.map(e => e.key)
                readonly property bool anyVisible: {
                    void SettingsStore.revision;
                    return section.sectionEntries.some(e => SettingsStore.isVisible(e.key));
                }

                Layout.fillWidth: true
                visible: section.anyVisible
                sectionId: section.modelData.id
                title: Translation.tr(section.modelData.title)
                icon: section.modelData.icon
                description: section.modelData.description ? Translation.tr(section.modelData.description) : ""
                bannerText: {
                    const reason = page.sectionBannerReason(section.modelData.id);
                    return reason ? Translation.tr(reason) : "";
                }

                Repeater {
                    model: section.sectionEntries

                    // Rows that depend on another row of this section are
                    // indented under it with a guide line.
                    delegate: Item {
                        id: rowSlot
                        required property var modelData
                        readonly property bool dependent: Logic.sectionDependencies(rowSlot.modelData, section.sectionKeys).length > 0

                        Layout.fillWidth: true
                        implicitHeight: rowLoader.implicitHeight
                        visible: (SettingsStore.revision, SettingsStore.isVisible(rowSlot.modelData.key))

                        Rectangle {
                            visible: rowSlot.dependent
                            anchors.left: parent.left
                            anchors.leftMargin: SettingsMetrics.dependentIndent / 2
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            anchors.topMargin: 6
                            anchors.bottomMargin: 6
                            implicitWidth: 2
                            radius: 1
                            color: Appearance.colors.colOutlineVariant
                        }

                        Loader {
                            id: rowLoader
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.leftMargin: rowSlot.dependent ? SettingsMetrics.dependentIndent : 0
                            Component.onCompleted: rowLoader.setSource(Qt.resolvedUrl(page.rowSources[rowSlot.modelData.widget] ?? "SettingsCustomRow.qml"), {
                                settingKey: rowSlot.modelData.key,
                                listedEntry: rowSlot.modelData,
                                page: page
                            })
                        }
                    }
                }
            }
        }

        // Empty state for pages whose registry has no entries yet.
        Rectangle {
            visible: page.entries.length === 0
            Layout.fillWidth: true
            implicitHeight: emptyLayout.implicitHeight + 48
            radius: SettingsMetrics.cardRadius
            color: Appearance.colors.colLayer1

            ColumnLayout {
                id: emptyLayout
                anchors.centerIn: parent
                spacing: 8

                MaterialSymbol {
                    Layout.alignment: Qt.AlignHCenter
                    text: "construction"
                    iconSize: 32
                    color: Appearance.colors.colSubtext
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: Translation.tr("No settings on this page yet.")
                    color: Appearance.colors.colSubtext
                }
            }
        }
    }
}
