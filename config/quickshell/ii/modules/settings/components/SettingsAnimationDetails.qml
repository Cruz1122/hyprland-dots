import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import "CurveMath.js" as CurveMath
import "AnimationsPageLogic.js" as PageLogic

// Unfolded part of a SettingsAnimationRow: the preview beside (or, below
// 640 px, above) the duration, curve and style controls. Every control
// writes through owner.commitField / owner.commitStyle (owner: the card row;
// not named "row", which would bind to itself in "row: row").
GridLayout {
    id: root

    property var owner: null
    readonly property alias preview: preview
    readonly property var card: root.owner?.card ?? null
    readonly property var parsed: root.owner?.parsedStyle ?? ({ kind: "none", percent: null, direction: "", known: true, raw: "" })
    readonly property var choices: root.owner?.styleChoices ?? []
    readonly property int styleIndex: root.parsed.known ? root.choices.findIndex(c => c.kind === root.parsed.kind) : root.choices.length
    readonly property var styleChoice: root.styleIndex >= 0 && root.styleIndex < root.choices.length ? root.choices[root.styleIndex] : null
    readonly property var styleModel: root.choices.map(c => ({ label: Translation.tr(c.label) })).concat(root.parsed.known ? [] : [{ label: Translation.tr("Not recognized: %1").arg(root.parsed.raw) }])
    readonly property var directionValues: ["", "top", "bottom", "left", "right"]
    readonly property var directionModel: [
        { label: Translation.tr("Nearest edge") },
        { label: Translation.tr("Top") },
        { label: Translation.tr("Bottom") },
        { label: Translation.tr("Left") },
        { label: Translation.tr("Right") }
    ]
    readonly property var defaultCurve: ({ name: "default", type: "bezier", points: CurveMath.DEFAULT_POINTS })

    // Puts the controls back on the shown value after a rejected write.
    function resync() {
        durationSlider.value = PageLogic.sliderMs(root.card?.speed ?? 0);
        percentSlider.value = root.parsed.percent ?? 80;
        styleCombo.currentIndex = root.styleIndex;
        directionCombo.currentIndex = Math.max(0, root.directionValues.indexOf(root.parsed.direction));
    }

    columns: root.width >= 640 ? 2 : 1
    columnSpacing: 20
    rowSpacing: 14

    SettingsAnimationPreview {
        id: preview
        objectName: "animationPreview"
        Layout.alignment: Qt.AlignTop | Qt.AlignHCenter
        Layout.preferredWidth: root.columns === 2 ? 260 : Math.min(root.width, 360)
        family: root.owner?.cardId ?? "windowsIn"
        kind: root.parsed.known ? root.parsed.kind : "none"
        percent: root.parsed.percent ?? -1
        direction: root.parsed.direction
        durationMs: CurveMath.speedToMs(root.card?.speed ?? 3)
        curve: root.owner?.curveDesc ?? root.defaultCurve
        enabled: root.card?.enabled === true
        reduceMotion: root.owner?.reduceMotion === true
    }

    ColumnLayout {
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignTop
        spacing: 14

        // Duration (a spring sets its own time).
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Duration")
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.Medium
                    color: Appearance.colors.colOnLayer1
                }

                StyledText {
                    objectName: "durationValue"
                    text: root.owner?.spring ? Translation.tr("≈ %1 ms (set by the spring)").arg(PageLogic.roundedSettleMs(root.owner.springMs))
                        : Translation.tr("%1 ms").arg(Math.round(durationSlider.value))
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.family: Appearance.font.family.numbers
                    font.variableAxes: Appearance.font.variableAxes.numbers
                    color: Appearance.colors.colOnLayer1
                }
            }

            StyledText {
                visible: root.owner?.spring === true
                Layout.fillWidth: true
                text: Translation.tr("A spring ignores the duration: its stiffness and damping decide how long it moves.")
                wrapMode: Text.Wrap
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }

            StyledSlider {
                id: durationSlider
                objectName: "durationSlider"
                visible: root.owner?.spring !== true
                Layout.fillWidth: true
                Layout.minimumWidth: 120
                from: PageLogic.MIN_MS
                to: PageLogic.MAX_MS
                stepSize: PageLogic.STEP_MS
                snapMode: Slider.SnapAlways
                stopIndicatorValues: []
                usePercentTooltip: false
                tooltipContent: Translation.tr("%1 ms").arg(Math.round(durationSlider.value))
                Accessible.name: Translation.tr("Duration")
                onPressedChanged: {
                    if (!durationSlider.pressed)
                        root.owner?.commitField("speed", CurveMath.msToSpeed(durationSlider.value));
                }
                onMoved: {
                    if (!durationSlider.pressed)
                        root.owner?.commitField("speed", CurveMath.msToSpeed(durationSlider.value));
                }

                SettingsFocusRing {
                    shown: durationSlider.visualFocus
                    ringRadius: 12
                }
            }

            Binding {
                target: durationSlider
                property: "value"
                value: PageLogic.sliderMs(root.card?.speed ?? 0)
                when: !durationSlider.pressed
                restoreMode: Binding.RestoreNone
            }

            RowLayout {
                visible: durationSlider.visible
                Layout.fillWidth: true

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Short")
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colSubtext
                }

                StyledText {
                    text: Translation.tr("Long")
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colSubtext
                }
            }
        }

        // Curve
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8

            StyledText {
                text: Translation.tr("Curve")
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.Medium
                color: Appearance.colors.colOnLayer1
            }

            SettingsCurvePicker {
                objectName: "curvePicker"
                Layout.fillWidth: true
                itemWidth: 100
                curves: root.owner?.catalog ?? []
                value: root.card?.curve ?? ""
                accessibleName: Translation.tr("Curve")
                onActivated: name => root.owner?.commitField("curve", name)
            }
        }

        // Style of the card's family (none for the border, the zoom and the shell panels).
        ColumnLayout {
            visible: root.choices.length > 0
            Layout.fillWidth: true
            spacing: 8

            StyledText {
                text: Translation.tr("Style")
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.Medium
                color: Appearance.colors.colOnLayer1
            }

            StyledComboBox {
                id: styleCombo
                objectName: "styleCombo"
                Layout.fillWidth: true
                Layout.maximumWidth: SettingsMetrics.selectWidth
                model: root.styleModel
                textRole: "label"
                Accessible.name: Translation.tr("Style")
                onActivated: index => {
                    // The "Not recognized" item keeps the value as it is.
                    if (index < root.choices.length)
                        root.owner?.commitStyle({ kind: root.choices[index].kind });
                }

                SettingsFocusRing {
                    shown: styleCombo.visualFocus
                    ringRadius: styleCombo.height / 2
                }
            }

            Binding {
                target: styleCombo
                property: "currentIndex"
                value: root.styleIndex
                restoreMode: Binding.RestoreNone
            }

            StyledText {
                objectName: "styleNote"
                visible: text.length > 0
                Layout.fillWidth: true
                text: root.styleChoice?.description ? Translation.tr("Now: %1").arg(Translation.tr(root.styleChoice.description)) : ""
                wrapMode: Text.Wrap
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }

            // popin: the size it grows from; slidefade: how far it moves.
            ColumnLayout {
                visible: root.styleChoice?.percent === true
                Layout.fillWidth: true
                spacing: 2

                RowLayout {
                    Layout.fillWidth: true

                    StyledText {
                        Layout.fillWidth: true
                        text: root.parsed.kind === "popin" ? Translation.tr("Starting size") : Translation.tr("Distance")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colOnLayer1
                    }

                    StyledText {
                        text: Translation.tr("%1%").arg(Math.round(percentSlider.value))
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.family: Appearance.font.family.numbers
                        font.variableAxes: Appearance.font.variableAxes.numbers
                        color: Appearance.colors.colOnLayer1
                    }
                }

                StyledSlider {
                    id: percentSlider
                    objectName: "percentSlider"
                    Layout.fillWidth: true
                    from: 0
                    to: 100
                    stepSize: 5
                    snapMode: Slider.SnapAlways
                    stopIndicatorValues: []
                    usePercentTooltip: false
                    tooltipContent: Translation.tr("%1%").arg(Math.round(percentSlider.value))
                    Accessible.name: root.parsed.kind === "popin" ? Translation.tr("Starting size") : Translation.tr("Distance")
                    onPressedChanged: {
                        if (!percentSlider.pressed)
                            root.owner?.commitStyle({ percent: Math.round(percentSlider.value) });
                    }
                    onMoved: {
                        if (!percentSlider.pressed)
                            root.owner?.commitStyle({ percent: Math.round(percentSlider.value) });
                    }

                    SettingsFocusRing {
                        shown: percentSlider.visualFocus
                        ringRadius: 12
                    }
                }

                Binding {
                    target: percentSlider
                    property: "value"
                    value: root.parsed.percent ?? 80
                    when: !percentSlider.pressed
                    restoreMode: Binding.RestoreNone
                }
            }

            // slide: the screen edge it uses.
            RowLayout {
                visible: (root.styleChoice?.directions ?? []).length > 0
                Layout.fillWidth: true
                spacing: 12

                StyledText {
                    text: Translation.tr("Side")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colOnLayer1
                }

                StyledComboBox {
                    id: directionCombo
                    objectName: "directionCombo"
                    Layout.fillWidth: true
                    Layout.maximumWidth: SettingsMetrics.selectWidth
                    model: root.directionModel
                    textRole: "label"
                    Accessible.name: Translation.tr("Side")
                    onActivated: index => root.owner?.commitStyle({ direction: root.directionValues[index] })

                    SettingsFocusRing {
                        shown: directionCombo.visualFocus
                        ringRadius: directionCombo.height / 2
                    }
                }

                Binding {
                    target: directionCombo
                    property: "currentIndex"
                    value: Math.max(0, root.directionValues.indexOf(root.parsed.direction))
                    restoreMode: Binding.RestoreNone
                }
            }
        }
    }
}
