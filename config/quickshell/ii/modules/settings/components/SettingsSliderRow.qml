import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import "../core/SettingsLogic.js" as Logic

// Numeric slider. `uiScale` multiplies the stored value for display
// (0.5 shown as 50 with unit "%"; percentages never show decimals). Writes
// once on release, or on each keyboard step. Under the track: minLabel and
// maxLabel, and a tick at the default value when the default is known.
SettingsRow {
    id: row

    readonly property real uiScale: row.entry?.uiScale ?? 1
    readonly property int decimals: Logic.displayDecimals(row.entry)
    readonly property string unit: row.entry?.unit ?? ""
    readonly property real stored: typeof row.value === "number" ? row.value : (row.entry?.min ?? 0)
    readonly property string minLabel: row.entry?.minLabel ? Translation.tr(row.entry.minLabel) : ""
    readonly property string maxLabel: row.entry?.maxLabel ? Translation.tr(row.entry.maxLabel) : ""
    readonly property bool hasDefault: typeof row.defaultValue === "number" && isFinite(row.defaultValue)
    // Default position on the track, 0..1 (-1 when unknown or out of range).
    readonly property real defaultFraction: {
        if (!row.hasDefault || control.to <= control.from)
            return -1;
        const f = (row.defaultValue * row.uiScale - control.from) / (control.to - control.from);
        return f >= 0 && f <= 1 ? f : -1;
    }

    controlPreferredWidth: 300
    controlFillsWidth: true
    focusVisible: control.visualFocus
    interactHandler: () => false
    needsValue: true

    // The locale's decimal separator, like the window preview's magnifier
    // ("2,0" in Spanish); no group separator, so 6500 stays "6500".
    function format(displayed) {
        const locale = Qt.locale();
        const number = Number(displayed).toLocaleString(locale, "f", row.decimals);
        return `${locale.groupSeparator.length > 0 ? number.split(locale.groupSeparator).join("") : number}${row.unit}`;
    }

    function commitControl() {
        row.commit(control.value / row.uiScale);
    }

    onRejected: control.value = row.stored * row.uiScale

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 0

        StyledSlider {
            id: control
            Layout.fillWidth: true
            Layout.minimumWidth: 120
            from: (row.entry?.min ?? 0) * row.uiScale
            to: (row.entry?.max ?? 1) * row.uiScale
            stepSize: (row.entry?.step ?? 0) * row.uiScale
            snapMode: stepSize > 0 ? Slider.SnapAlways : Slider.NoSnap
            stopIndicatorValues: []
            usePercentTooltip: false
            tooltipContent: row.format(control.value)
            Accessible.name: row.label
            onPressedChanged: {
                if (!control.pressed)
                    row.commitControl();
            }
            onMoved: {
                if (!control.pressed)
                    row.commitControl();
            }
        }

        // Scale captions and the default mark, aligned with the track.
        Item {
            objectName: "sliderScale"
            visible: row.minLabel.length > 0 || row.maxLabel.length > 0 || row.defaultFraction >= 0
            Layout.fillWidth: true
            implicitHeight: Math.max(defaultTick.implicitHeight, row.minLabel.length > 0 || row.maxLabel.length > 0 ? minText.implicitHeight + 4 : 0)

            Rectangle {
                id: defaultTick
                objectName: "defaultTick"
                visible: row.defaultFraction >= 0
                x: control.leftPadding + row.defaultFraction * control.availableWidth - implicitWidth / 2
                y: 0
                implicitWidth: 2
                implicitHeight: 6
                radius: 1
                color: Appearance.colors.colOutline
                Accessible.name: Translation.tr("Default: %1").arg(row.format(row.defaultValue * row.uiScale))
            }

            StyledText {
                id: minText
                anchors.left: parent.left
                anchors.leftMargin: control.leftPadding
                anchors.bottom: parent.bottom
                visible: text.length > 0
                text: row.minLabel
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colSubtext
            }

            StyledText {
                anchors.right: parent.right
                anchors.rightMargin: control.rightPadding
                anchors.bottom: parent.bottom
                visible: text.length > 0
                text: row.maxLabel
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colSubtext
            }
        }
    }

    StyledText {
        objectName: "sliderValue"
        Layout.preferredWidth: valueMetrics.width + 4
        Layout.alignment: Qt.AlignTop
        Layout.topMargin: (control.implicitHeight - implicitHeight) / 2
        horizontalAlignment: Text.AlignRight
        text: row.format(control.value)
        color: Appearance.colors.colOnLayer1
        font.family: Appearance.font.family.numbers
        font.variableAxes: Appearance.font.variableAxes.numbers
    }

    TextMetrics {
        id: valueMetrics
        font.family: Appearance.font.family.numbers
        font.pixelSize: Appearance.font.pixelSize.small
        text: row.format(-Math.max(Math.abs(control.from), Math.abs(control.to)))
    }

    Binding {
        target: control
        property: "value"
        value: row.stored * row.uiScale
        when: !control.pressed
        restoreMode: Binding.RestoreNone
    }
}
