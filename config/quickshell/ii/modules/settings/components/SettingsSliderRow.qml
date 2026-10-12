import QtQuick
import QtQuick.Layouts
import qs.modules.common.widgets
import qs.modules.settings.components

SettingsResponsiveRow {
    id: root

    property alias value: sliderControl.value
    property alias from: sliderControl.from
    property alias to: sliderControl.to
    property alias stepSize: sliderControl.stepSize
    property alias stopIndicatorValues: sliderControl.stopIndicatorValues
    property alias usePercentTooltip: sliderControl.usePercentTooltip
    property real textWidth: 120

    StyledSlider {
        id: sliderControl
        Layout.alignment: Qt.AlignRight
        Accessible.name: root.title
    }
}
