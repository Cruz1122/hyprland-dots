import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs.modules.settings.core
import "../backends/AnimationLogic.js" as AL
import "CurveMath.js" as CurveMath
import "AnimationsPageLogic.js" as PageLogic

// One Hyprland animation card (widget "animation", docs/settings.md
// "Animations page"). Folded it shows the summary ("Pop in 80% · 300 ms ·
// Quick start, gentle stop") with the fold toggle, ▶ and the enable switch;
// unfolded it adds SettingsAnimationPreview and the controls: duration (a
// spring shows its own time instead), curve and the style of the card's
// family. A search hit or a dependency jump unfolds it.
//
// The value is { enabled, speed, curve, style } from SettingsStore; every
// change goes through commit() (SettingsStore.write). The backend's
// read-only helpers come from SettingsStore.backends.animation.
SettingsRow {
    id: row

    readonly property string cardId: row.entry?.path ?? ""
    readonly property var backend: SettingsStore.backends?.animation ?? null
    readonly property var card: row.value && typeof row.value === "object" ? row.value : null
    readonly property var catalog: {
        void SettingsStore.revision;
        return row.backend?.curveCatalog() ?? [];
    }
    readonly property var parts: {
        void SettingsStore.revision;
        void row.card;
        return row.card && row.backend ? row.backend.summaryParts(row.cardId) : null;
    }
    readonly property var parsedStyle: AL.parseStyle(row.cardId, row.card?.style ?? "")
    // Shell panels keep their own entrance (rules.lua): their cards set only
    // the duration and the curve.
    readonly property bool panelCard: row.cardId === "layersIn" || row.cardId === "layersOut"
    readonly property var styleChoices: row.panelCard ? [] : PageLogic.styleChoices(row.backend?.styleOptions(row.cardId) ?? [], row.parsedStyle)
    readonly property var curveDesc: PageLogic.findCurve(row.catalog, row.card?.curve ?? "")
    readonly property bool spring: row.curveDesc?.type === "spring"
    readonly property real springMs: row.spring ? CurveMath.springSettleMs(row.curveDesc) : 0
    // Panel cards leave the style out: rules.lua decides each panel's entrance.
    readonly property string summary: PageLogic.summaryText(row.panelCard && row.parts ? Object.assign({}, row.parts, { style: null }) : row.parts,
        row.catalog, text => Translation.tr(text), row.springMs)
    readonly property bool reduceMotion: Config.options?.appearance?.animations?.reduceMotion === true
    property bool unfolded: false
    property string lastValue: JSON.stringify(row.card)

    stacked: true
    controlFillsWidth: true
    needsValue: true
    focusVisible: false
    activateHandler: () => {
        if (!row.unfolded)
            row.unfolded = true;
    }
    interactHandler: () => false
    Accessible.description: [row.summary, row.accessibleDescription()].filter(t => t.length > 0).join(". ")

    function toggleFold() {
        row.unfolded = !row.unfolded;
    }

    function commitField(field, fieldValue) {
        if (!row.card)
            return false;
        return row.commit(PageLogic.withField(row.card, field, fieldValue));
    }

    function commitStyle(change) {
        if (!row.card)
            return false;
        return row.commitField("style", PageLogic.restyle(row.cardId, row.parsedStyle, change, row.styleChoices, 80));
    }

    // ▶: unfolds the card and plays the preview, also under reduceMotion.
    function playPreview() {
        row.unfolded = true;
        Qt.callLater(() => details.item?.preview.play());
    }

    // A search hit or a dependency jump highlights the row: show its controls.
    onHighlightedChanged: {
        if (row.highlighted)
            row.unfolded = true;
    }

    // Any change of the card's value (a control released, undo, a preset)
    // replays the preview; replay() does nothing under reduceMotion.
    onCardChanged: {
        const now = JSON.stringify(row.card);
        if (now === row.lastValue)
            return;
        row.lastValue = now;
        if (row.unfolded)
            details.item?.preview.replay();
    }

    onRejected: details.item?.resync()

    // The reset button sits at the top of the stacked control column, beside
    // the summary line, instead of centred on the unfolded controls.
    Component.onCompleted: {
        const reset = row.page?.findItem?.(row, "resetButton") ?? null;
        if (reset)
            reset.Layout.alignment = Qt.AlignTop;
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 10

        RowLayout {
            objectName: "animationHeader"
            Layout.fillWidth: true
            spacing: 8

            SettingsIconButton {
                id: foldToggle
                objectName: "foldToggle"
                iconName: "expand_more"
                iconRotation: row.unfolded ? 180 : 0
                tooltip: row.unfolded ? Translation.tr("Hide the controls of “%1”").arg(row.label) : Translation.tr("Show the controls of “%1”").arg(row.label)
                size: 32
                iconSize: 20
                Accessible.checkable: true
                Accessible.checked: row.unfolded
                onClicked: row.toggleFold()
                Keys.onReturnPressed: row.toggleFold()
                Keys.onEnterPressed: row.toggleFold()

                Behavior on iconRotation {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
            }

            StyledText {
                objectName: "animationSummary"
                Layout.fillWidth: true
                text: row.summary
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnLayer1

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: row.toggleFold()
                }
            }

            SettingsIconButton {
                objectName: "playButton"
                iconName: "play_arrow"
                tooltip: Translation.tr("Play the preview of “%1”").arg(row.label)
                size: 32
                iconSize: 20
                enabled: row.card?.enabled === true
                onClicked: row.playPreview()
                Keys.onReturnPressed: row.playPreview()
                Keys.onEnterPressed: row.playPreview()
            }

            StyledSwitch {
                id: enableSwitch
                objectName: "enableSwitch"
                Accessible.name: Translation.tr("Animate “%1”").arg(row.label)
                onToggled: {
                    if (!row.commitField("enabled", enableSwitch.checked))
                        enableSwitch.checked = row.card?.enabled === true;
                }

                SettingsFocusRing {
                    shown: enableSwitch.visualFocus
                    ringRadius: enableSwitch.height / 2
                }
            }

            Binding {
                target: enableSwitch
                property: "checked"
                value: row.card?.enabled === true
                restoreMode: Binding.RestoreNone
            }
        }

        Loader {
            id: details
            objectName: "animationDetails"
            Layout.fillWidth: true
            active: row.unfolded
            visible: row.unfolded
            sourceComponent: SettingsAnimationDetails {
                owner: row
            }
        }
    }
}
