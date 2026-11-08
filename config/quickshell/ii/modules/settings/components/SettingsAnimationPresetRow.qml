import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs.modules.settings.core
import "AnimationsPageLogic.js" as PageLogic

// Animation preset (widget "animationPreset", docs/settings.md "Animations
// page"): Default · Agile · Smooth · Bouncy · Minimal, plus a read-only
// "Custom" while the cards match none of them. The backend writes the 10
// cards of a preset in one change set. Applying a preset over a custom state
// shows a 10 s bar whose [Undo] puts the previous cards back: a write for
// each card that was in the generated file and a reset for the others, all
// in this event-loop turn, so the backend sends them as one batch.
SettingsRow {
    id: row

    readonly property var backend: SettingsStore.backends?.animation ?? null
    readonly property var options: {
        void SettingsStore.revision;
        return PageLogic.presetChoices(row.backend?.presets() ?? [], row.value).map(o => Object.assign({}, o, {
            label: Translation.tr(o.label),
            description: o.description ? Translation.tr(o.description) : ""
        }));
    }
    readonly property int currentIndex: row.options.findIndex(o => o.value === row.value)
    // Cards a preset writes (the animation cards of the registry).
    readonly property var cardKeys: SettingsRegistry.allEntries().filter(e => e.backend === "animation" && e.widget === "animation").map(e => e.key)
    // [{ key, managed, value }] captured before the last preset that replaced
    // a custom state, while its Undo bar shows; null otherwise.
    property var undoSnapshot: null
    property string undoLabel: ""

    stacked: true
    controlFillsWidth: true
    needsValue: true
    // Only for a known value: without the backend the preset is unknown
    // ("—"), never the Default that an empty managed state would suggest.
    optionNote: !row.showPlaceholder && row.available && row.currentIndex >= 0 && row.options[row.currentIndex].description
        ? Translation.tr("Now: %1").arg(row.options[row.currentIndex].description) : ""
    interactHandler: () => false

    // Writes a preset; over a custom state it keeps the cards for Undo. A
    // preset applied while the Undo bar shows keeps that snapshot (Undo
    // still goes back to the custom state) but renames the bar and gives it
    // its full time again.
    function applyPreset(value) {
        const snapshot = row.value === "custom" ? row.cardKeys.map(key => ({
            key: key,
            managed: SettingsStore.isModified(key),
            value: SettingsStore.value(key)
        })) : null;
        if (!row.commit(value))
            return false;
        if (snapshot)
            row.undoSnapshot = snapshot;
        if (row.undoSnapshot !== null) {
            row.undoLabel = row.options.find(o => o.value === value)?.label ?? String(value);
            undoTimer.restart();
        }
        return true;
    }

    function undo() {
        const plan = PageLogic.undoPlan(row.undoSnapshot);
        row.undoSnapshot = null;
        undoTimer.stop();
        for (const step of plan) {
            if (step.action === "write")
                SettingsStore.write(step.key, step.value);
            else
                SettingsStore.reset(step.key);
        }
    }

    function select(index) {
        const option = row.options[index];
        if (!option || option.readOnly)
            return false;
        return row.applyPreset(option.value);
    }

    Timer {
        id: undoTimer
        interval: 10000 // motion-ok: timeout of the Undo bar, not motion
        onTriggered: row.undoSnapshot = null
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 10

        Flow {
            id: choices
            objectName: "presetChoices"
            Layout.fillWidth: true
            spacing: 6

            Repeater {
                id: presetRepeater
                model: row.options

                delegate: RippleButton {
                    id: choice
                    required property var modelData
                    required property int index
                    readonly property bool selected: choice.index === row.currentIndex

                    objectName: "preset:" + choice.modelData.value
                    implicitHeight: SettingsMetrics.controlHeight
                    implicitWidth: choiceContent.implicitWidth + 28
                    buttonRadius: height / 2
                    enabled: !choice.modelData.readOnly
                    toggled: choice.selected
                    colBackground: Appearance.colors.colLayer2
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    colBackgroundToggled: Appearance.colors.colSecondaryContainer
                    colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
                    colRipple: Appearance.colors.colLayer2Active
                    colRippleToggled: Appearance.colors.colSecondaryContainerActive
                    Accessible.name: choice.modelData.label
                    Accessible.description: choice.modelData.description
                    Accessible.role: Accessible.RadioButton
                    Accessible.checkable: true
                    Accessible.checked: choice.selected
                    onClicked: row.select(choice.index)
                    Keys.onLeftPressed: row.select(choice.index - 1) && presetRepeater.itemAt(choice.index - 1)?.forceActiveFocus()
                    Keys.onRightPressed: row.select(choice.index + 1) && presetRepeater.itemAt(choice.index + 1)?.forceActiveFocus()

                    contentItem: Item {
                        implicitWidth: choiceContent.implicitWidth
                        implicitHeight: choiceContent.implicitHeight

                        RowLayout {
                            id: choiceContent
                            anchors.centerIn: parent
                            spacing: 6

                            MaterialSymbol {
                                visible: choice.selected || choice.modelData.readOnly
                                text: choice.modelData.readOnly ? "tune" : "check"
                                iconSize: 16
                                color: choice.selected ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer2
                            }

                            StyledText {
                                text: choice.modelData.label
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.weight: choice.selected ? Font.Medium : Font.Normal
                                color: choice.selected ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer2
                            }
                        }
                    }

                    SettingsFocusRing {
                        shown: choice.visualFocus
                        ringRadius: choice.height / 2
                    }
                }
            }
        }

        // Undo of a preset that replaced a custom state.
        Rectangle {
            objectName: "presetUndoBar"
            visible: row.undoSnapshot !== null
            Layout.fillWidth: true
            implicitHeight: undoLayout.implicitHeight + 16
            radius: SettingsMetrics.controlRadius
            color: Appearance.colors.colSecondaryContainer

            RowLayout {
                id: undoLayout
                anchors {
                    left: parent.left
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                    leftMargin: 14
                    rightMargin: 6
                }
                spacing: 8

                MaterialSymbol {
                    text: "history"
                    iconSize: 18
                    color: Appearance.colors.colOnSecondaryContainer
                }

                StyledText {
                    objectName: "presetUndoText"
                    Layout.fillWidth: true
                    text: Translation.tr("“%1” replaced your custom animations.").arg(row.undoLabel)
                    wrapMode: Text.Wrap
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colOnSecondaryContainer
                }

                SettingsButton {
                    objectName: "presetUndo"
                    kind: "text"
                    iconName: "undo"
                    text: Translation.tr("Undo")
                    onClicked: row.undo()
                }
            }
        }
    }
}
