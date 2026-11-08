import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs.modules.settings.core
import "../core/SettingsLogic.js" as Logic

// Base of every settings row: icon, label, description and state on the
// left, the control (default children) on the right, or below the text when
// the row is narrower than SettingsMetrics.rowStackWidth.
//
// Variants show SettingsStore values through Binding { restoreMode:
// Binding.RestoreNone } and call commit() only on user interaction. When
// commit() is rejected they receive rejected() and resync their control.
//
// Comprehension (docs/settings.md "Rows"): a "?" toggle opens entry.help
// inline; chips on the label line say when a change applies, what it costs
// and which setting it requires (a link that reveals it); a status line shows
// the backend's statusNote; with the backend unavailable (or no value) the
// control is replaced by "—" instead of a made-up value.
Item {
    id: row

    property string settingKey: ""
    // Entry as listed by the page (an alias copy carries aliasOf/homePageId).
    property var listedEntry: null
    readonly property var entry: SettingsRegistry.entry(row.settingKey)
    // Page rendering the row: provides actions, customDelegates and infoValues.
    property var page: null

    readonly property string label: Translation.tr(row.entry?.label ?? row.settingKey)
    readonly property string description: row.entry?.description ? Translation.tr(row.entry.description) : ""
    readonly property string note: row.entry?.note ? Translation.tr(row.entry.note) : ""
    readonly property string help: row.entry?.help ? Translation.tr(row.entry.help) : ""
    readonly property bool helpOpen: row.help.length > 0 && SettingsSession.isHelpOpen(row.settingKey)
    readonly property string iconName: row.entry?.icon ?? ""
    readonly property bool writable: !!row.entry && row.entry.backend !== "action" && row.entry.backend !== "readonly" && row.entry.type !== "action" && row.entry.type !== "info"
    // Variants set the "Now: …" text of the selected option.
    property string optionNote: ""
    readonly property string statusNote: {
        void SettingsStore.revision;
        const note = SettingsStore.statusNote(row.settingKey);
        return note ? Translation.tr(note) : "";
    }

    readonly property var value: (SettingsStore.revision, SettingsStore.value(row.settingKey))
    readonly property var defaultValue: (SettingsStore.revision, SettingsStore.defaultValue(row.settingKey))
    readonly property bool modified: row.writable && (SettingsStore.revision, SettingsStore.isModified(row.settingKey))
    readonly property bool available: (SettingsStore.revision, SettingsStore.isAvailable(row.settingKey))
    readonly property bool rowEnabled: (SettingsStore.revision, SettingsStore.isEnabled(row.settingKey)) && row.extraEnabled
    // Variants may add their own requirement (for example a missing action handler).
    property bool extraEnabled: true
    property string extraDisabledReason: ""
    // Setting this row waits for: { key, text } while another setting's
    // value disables it, else null. Shown as the "Requires …" chip.
    readonly property var requires: {
        void SettingsStore.revision;
        if (row.rowEnabled || !row.available || row.extraDisabledReason.length > 0)
            return null;
        const cond = SettingsStore.blockingCondition(row.settingKey);
        let leaf = cond;
        while (leaf?.not !== undefined)
            leaf = leaf.not;
        if (leaf?.key === undefined)
            return null;
        return { key: leaf.key, text: Logic.dependencyText(cond, SettingsRegistry.entry(leaf.key), text => Translation.tr(text)) };
    }
    readonly property string disabledReason: row.rowEnabled ? "" : row.computeDisabledReason()
    // The section shows this reason once in its banner (SettingsPage).
    readonly property bool reasonInBanner: !row.available && !!row.page && row.page.sectionBannerReason(row.listedEntry?.section ?? row.entry?.section ?? "") === SettingsStore.unavailableReason(row.settingKey)
    readonly property var chips: Logic.rowChips(row.entry, row.requires).map(c => Object.assign({}, c, {
        text: c.kind === "requires" ? c.label : Translation.tr(c.label)
    }))
    // Rows that show a value (switch, slider, …) need one: without it the
    // control would show a made-up state, so "—" replaces it.
    property bool needsValue: false
    property bool placeholderWhenUnavailable: true
    readonly property bool showPlaceholder: row.writable && ((row.placeholderWhenUnavailable && !row.available) || (row.needsValue && row.value === undefined))
    readonly property string resetText: Logic.resetText(row.entry, row.defaultValue, text => Translation.tr(text))

    property bool highlighted: false
    property bool busy: false
    property string errorText: ""
    readonly property bool hovered: hoverHandler.hovered

    // Forces the control below the text (text areas, lists, custom widgets).
    property bool stacked: false
    // In the stacked layout the control takes the whole width.
    property bool controlFillsWidth: false
    // Width of the control column in the side-by-side layout (-1: implicit).
    property real controlPreferredWidth: -1
    readonly property real availableWidth: row.width - 2 * SettingsMetrics.rowHorizontalPadding
    // While "—" replaces the control, the row lays out as if its control were
    // that short text.
    readonly property real controlWidthHint: row.showPlaceholder ? valuePlaceholder.implicitWidth : (row.controlPreferredWidth > 0 ? row.controlPreferredWidth : controlBox.implicitWidth)
    readonly property bool compact: (row.stacked && !row.showPlaceholder) || row.width < SettingsMetrics.rowStackWidth || row.controlWidthHint > row.availableWidth * 0.55
    // Set by variants from their control (visualFocus) to draw the focus ring.
    property bool focusVisible: false

    // Row click (outside the control). interactHandler performs the primary
    // interaction for the harness driver; both return false when unsupported.
    property var activateHandler: null
    property var interactHandler: null

    default property alias controlData: controlBox.data

    signal rejected()

    objectName: "row:" + row.settingKey
    implicitWidth: layout.implicitWidth + 2 * SettingsMetrics.rowHorizontalPadding
    implicitHeight: layout.implicitHeight + 2 * SettingsMetrics.rowVerticalPadding
    Accessible.name: row.label
    Accessible.description: row.accessibleDescription()

    // Description, help, chips and status as one translated text. A row
    // disabled by another setting has the same "Requires …" sentence as its
    // chip and its disabled reason: it is said once, by the chip.
    function accessibleDescription() {
        const parts = [row.description, row.help, row.optionNote, ...row.chips.map(c => c.text), row.statusNote, row.requires ? "" : row.disabledReason, row.errorText];
        return parts.filter(p => p.length > 0).map(p => p.replace(/[.\s]+$/, "")).join(". ");
    }

    function toggleHelp() {
        SettingsSession.setHelpOpen(row.settingKey, !row.helpOpen);
    }

    // Reveals the setting this row requires: on this page when it is here,
    // otherwise on its own page (settings.qml reveal).
    function revealDependency(key) {
        if (row.page?.scrollTo?.(key))
            return;
        SettingsSession.requestReveal(key);
    }

    function computeDisabledReason() {
        if (row.extraDisabledReason.length > 0)
            return row.extraDisabledReason;
        if (!SettingsStore.isAvailable(row.settingKey))
            return Translation.tr(SettingsStore.unavailableReason(row.settingKey));
        const cond = SettingsStore.blockingCondition(row.settingKey);
        if (cond?.capability !== undefined)
            return Translation.tr(Logic.capabilityReason(cond.capability));
        if (row.requires)
            return row.requires.text;
        return Translation.tr("Not available");
    }

    function commit(newValue) {
        const ok = SettingsStore.write(row.settingKey, newValue);
        if (!ok)
            row.rejected();
        return ok;
    }

    function resetToDefault() {
        if (!SettingsStore.reset(row.settingKey))
            row.rejected();
    }

    function interact() {
        return row.rowEnabled && typeof row.interactHandler === "function" ? row.interactHandler() !== false : false;
    }

    function pulse() {
        row.highlighted = true;
        pulseAnimation.restart();
    }

    Connections {
        target: SettingsStore
        function onFailed(key, message) {
            if (key === row.settingKey)
                row.errorText = Translation.tr(message);
        }
        function onCommitted(key) {
            if (key === row.settingKey)
                row.errorText = "";
        }
    }

    HoverHandler {
        id: hoverHandler
    }

    // Clicks on the text or the empty part of the row; controls above it
    // receive their own clicks.
    MouseArea {
        anchors.fill: parent
        enabled: row.rowEnabled && typeof row.activateHandler === "function"
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: row.activateHandler()
    }

    Rectangle {
        id: background
        anchors.fill: parent
        radius: SettingsMetrics.rowRadius
        color: row.hovered && row.rowEnabled ? Appearance.colors.colLayer1Hover : "transparent"

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }
    }

    Rectangle {
        id: highlight
        anchors.fill: parent
        radius: SettingsMetrics.rowRadius
        color: Appearance.colors.colPrimaryContainer
        opacity: 0
        visible: opacity > 0
    }

    SequentialAnimation {
        id: pulseAnimation
        loops: 2
        NumberAnimation { target: highlight; property: "opacity"; to: 0.9; duration: 220; easing.type: Easing.OutCubic } // motion-ok: search highlight pulse polled by the harness
        NumberAnimation { target: highlight; property: "opacity"; to: 0.35; duration: 380; easing.type: Easing.InOutCubic } // motion-ok: search highlight pulse polled by the harness
        onFinished: fadeOut.start()
    }

    NumberAnimation {
        id: fadeOut
        target: highlight
        property: "opacity"
        to: 0
        duration: 900 // motion-ok: search highlight pulse polled by the harness
        easing.type: Easing.InOutCubic
        onFinished: row.highlighted = false
    }

    SettingsFocusRing {
        target: background
        shown: row.focusVisible
        ringRadius: SettingsMetrics.rowRadius
    }

    GridLayout {
        id: layout
        anchors {
            left: parent.left
            right: parent.right
            verticalCenter: parent.verticalCenter
            leftMargin: SettingsMetrics.rowHorizontalPadding
            rightMargin: SettingsMetrics.rowHorizontalPadding
        }
        columns: row.compact ? 1 : 2
        columnSpacing: 20
        rowSpacing: 12

        RowLayout {
            id: textRow
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 14

            MaterialSymbol {
                id: leadingIcon
                visible: row.iconName.length > 0
                Layout.alignment: Qt.AlignTop
                Layout.topMargin: 1
                text: row.iconName
                iconSize: 22
                color: row.rowEnabled ? Appearance.colors.colOnSurfaceVariant : Appearance.colors.colOnLayer1Inactive
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                // Label, modified dot, help toggle and chips; the chips wrap
                // to the next line when the text column is narrow.
                Flow {
                    id: labelLine
                    Layout.fillWidth: true
                    spacing: 8
                    readonly property real lineBox: Math.max(labelMetrics.height, 24)
                    // The modified dot and the help toggle stay beside a
                    // wrapped label; only chips may move to the next line.
                    readonly property real besideLabel: (row.modified ? 8 + spacing : 0) + (row.help.length > 0 ? 24 + spacing : 0)

                    // Capped at its natural width so the decorations sit
                    // right after the text; wraps when the row is narrow.
                    StyledText {
                        id: labelText
                        width: Math.max(0, Math.min(Math.ceil(labelMetrics.advanceWidth) + 1, labelLine.width - labelLine.besideLabel)) // size-ok: wraps inside the Flow
                        topPadding: (labelLine.lineBox - labelMetrics.height) / 2
                        bottomPadding: topPadding
                        text: row.label
                        wrapMode: Text.Wrap
                        font.pixelSize: Appearance.font.pixelSize.normal
                        color: row.rowEnabled ? Appearance.colors.colOnLayer1 : Appearance.colors.colOnLayer1Inactive
                    }

                    // Natural width of the label: a wrapped Text reports its
                    // wrapped width as implicitWidth, which would feed back.
                    TextMetrics {
                        id: labelMetrics
                        font: labelText.font
                        text: row.label
                    }

                    LineItem {
                        visible: row.modified
                        lineHeight: labelLine.lineBox

                        Rectangle {
                            implicitWidth: 8
                            implicitHeight: 8
                            radius: 4
                            color: Appearance.colors.colPrimary
                            Accessible.name: Translation.tr("Modified")
                        }
                    }

                    LineItem {
                        visible: row.help.length > 0
                        lineHeight: labelLine.lineBox

                        SettingsIconButton {
                            objectName: "helpToggle"
                            iconName: "help"
                            tooltip: Translation.tr("Help: %1").arg(row.label)
                            size: 24
                            iconSize: 17
                            toggled: row.helpOpen
                            colBackgroundToggled: Appearance.colors.colSecondaryContainer
                            colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
                            iconColor: row.helpOpen ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colSubtext
                            Accessible.checkable: true
                            Accessible.checked: row.helpOpen
                            onClicked: row.toggleHelp()
                            Keys.onReturnPressed: row.toggleHelp()
                            Keys.onEnterPressed: row.toggleHelp()
                        }
                    }

                    Repeater {
                        model: row.chips

                        delegate: LineItem {
                            id: chipItem
                            required property var modelData
                            lineHeight: labelLine.lineBox

                            SettingsChip {
                                objectName: "chip:" + chipItem.modelData.id
                                label: chipItem.modelData.text
                                iconName: chipItem.modelData.icon
                                interactive: chipItem.modelData.kind === "requires"
                                maximumWidth: labelLine.width
                                onClicked: {
                                    if (chipItem.modelData.kind === "requires")
                                        row.revealDependency(chipItem.modelData.target);
                                }
                            }
                        }
                    }
                }

                StyledText {
                    visible: text.length > 0
                    Layout.fillWidth: true
                    text: row.description
                    wrapMode: Text.Wrap
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }

                StyledText {
                    objectName: "optionNote"
                    visible: text.length > 0
                    Layout.fillWidth: true
                    text: row.optionNote
                    wrapMode: Text.Wrap
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }

                StyledText {
                    visible: text.length > 0
                    Layout.fillWidth: true
                    text: row.note
                    wrapMode: Text.Wrap
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.italic: true
                    color: Appearance.colors.colSubtext
                }

                // entry.help, inline while the "?" toggle is on.
                RowLayout {
                    objectName: "helpText"
                    visible: row.helpOpen
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    spacing: 10

                    Rectangle {
                        Layout.fillHeight: true
                        implicitWidth: 2
                        radius: 1
                        color: Appearance.colors.colPrimary
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: row.help
                        wrapMode: Text.Wrap
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colOnLayer1
                    }
                }

                StatusLine {
                    objectName: "statusNote"
                    shown: row.statusNote.length > 0
                    iconName: "info"
                    text: row.statusNote
                    italic: true
                    color: Appearance.colors.colSubtext
                }

                StatusLine {
                    objectName: "lockReason"
                    shown: row.disabledReason.length > 0 && !row.requires && !row.reasonInBanner
                    iconName: "lock"
                    text: row.disabledReason
                    color: Appearance.colors.colSubtext
                }

                StatusLine {
                    shown: row.errorText.length > 0
                    iconName: "error"
                    text: row.errorText
                    color: Appearance.colors.colError
                }

                StatusLine {
                    shown: !!row.listedEntry?.aliasOf && row.page?.pageId !== row.listedEntry?.homePageId
                    iconName: "link"
                    text: Translation.tr("Also in %1").arg(Translation.tr(SettingsRegistry.page(row.listedEntry?.homePageId ?? "")?.title ?? ""))
                    color: Appearance.colors.colSubtext
                }
            }
        }

        RowLayout {
            id: controlRow
            Layout.alignment: row.compact ? Qt.AlignLeft | Qt.AlignVCenter : Qt.AlignRight | Qt.AlignVCenter
            Layout.fillWidth: row.compact && row.controlFillsWidth && !row.showPlaceholder
            Layout.preferredWidth: !row.compact && row.controlPreferredWidth > 0 && !row.showPlaceholder ? row.controlPreferredWidth : -1
            Layout.leftMargin: row.compact && leadingIcon.visible ? leadingIcon.implicitWidth + textRow.spacing : 0
            spacing: 6

            SettingsIconButton {
                objectName: "resetButton"
                visible: row.modified && row.rowEnabled
                Layout.alignment: Qt.AlignVCenter
                iconName: "restart_alt"
                tooltip: row.resetText
                size: 32
                iconSize: 18
                onClicked: row.resetToDefault()
            }

            RowLayout {
                id: controlBox
                objectName: "rowControl"
                visible: !row.showPlaceholder
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 8
                enabled: row.rowEnabled
                opacity: row.rowEnabled ? 1 : 0.5
            }

            // No value to show (backend unavailable): never a made-up one.
            StyledText {
                id: valuePlaceholder
                objectName: "valuePlaceholder"
                visible: row.showPlaceholder
                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                text: "—"
                color: Appearance.colors.colOnLayer1Inactive
                Accessible.name: Translation.tr("No value")
            }
        }
    }

    // Centers a decoration of the label line on the first text line.
    component LineItem: Item {
        default property alias content: holder.data
        property real lineHeight: 24
        implicitWidth: holder.implicitWidth
        implicitHeight: lineHeight

        RowLayout {
            id: holder
            anchors.verticalCenter: parent.verticalCenter
            spacing: 0
        }
    }

    component StatusLine: RowLayout {
        id: statusLine
        property bool shown: false
        property string iconName: ""
        property string text: ""
        property bool italic: false
        property color color
        visible: statusLine.shown
        Layout.fillWidth: true
        Layout.topMargin: 2
        spacing: 6

        MaterialSymbol {
            Layout.alignment: Qt.AlignTop
            text: statusLine.iconName
            iconSize: 15
            color: statusLine.color
        }

        StyledText {
            objectName: statusLine.objectName.length > 0 ? statusLine.objectName + "Text" : ""
            Layout.fillWidth: true
            text: statusLine.text
            wrapMode: Text.Wrap
            font.pixelSize: Appearance.font.pixelSize.smaller
            font.italic: statusLine.italic
            color: statusLine.color
        }
    }
}
