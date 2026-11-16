import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.UPower

Rectangle {
    id: root

    property var screen: root.QsWindow.window?.screen
    property var brightnessMonitor: Brightness.getMonitorForScreen(screen)

    implicitWidth: contentItem.implicitWidth + root.horizontalPadding * 2
    implicitHeight: contentItem.implicitHeight + root.verticalPadding * 2
    radius: Appearance.rounding.normal
    color: Appearance.colors.colLayer1
    property real verticalPadding: 2
    property real horizontalPadding: 12

    Column {
        id: contentItem
        anchors {
            fill: parent
            leftMargin: root.horizontalPadding
            rightMargin: root.horizontalPadding
            topMargin: root.verticalPadding
            bottomMargin: root.verticalPadding
        }

        Loader {
            anchors {
                left: parent.left
                right: parent.right
            }
            visible: active
            active: Config.options.sidebar.quickSliders.showBrightness
            sourceComponent: QuickSlider {
                materialSymbol: "light_mode"
                secondaryMaterialSymbol: "wb_twilight"
                stopIndicatorValues: Hyprsunset.gamma !== 100 && root.brightnessMonitor?.brightness !== 0 ? [0.3 + root.brightnessMonitor?.brightness * 0.7] : []
                value: Hyprsunset.gamma === 100? 0.3 + root.brightnessMonitor?.brightness * 0.7 : (Hyprsunset.gamma - Hyprsunset.gammaLowerLimit) / (100 - Hyprsunset.gammaLowerLimit) * 0.3
                tooltipContent: Hyprsunset.gamma === 100 ? `${Math.round(root.brightnessMonitor?.brightness * 100)}%` : `${Translation.tr("Gamma")} ${Hyprsunset.gamma}%`
                onMoved: {
                    if (value >= 0.3) {
                        // 0.3 - 1.0 brightness
                        root.brightnessMonitor.setBrightness((value - 0.3) / 0.7);
                        if (Hyprsunset.gamma !== 100) {
                            Hyprsunset.setGamma(100);
                        }
                    } else {
                        // 0 - 0.3 gamma
                        if (root.brightnessMonitor.brightness !== 0) {
                            root.brightnessMonitor.setBrightness(0);
                        }
                        Hyprsunset.setGamma((value / 0.3 * (100 - Hyprsunset.gammaLowerLimit) + Hyprsunset.gammaLowerLimit));
                    }
                }
            }
        }

        Loader {
            anchors {
                left: parent.left
                right: parent.right
            }
            visible: active
            active: Config.options.sidebar.quickSliders.showVolume
            sourceComponent: QuickSlider {
                materialSymbol: "volume_up"
                value: Audio.sink.audio.volume
                onMoved: {
                    Audio.sink.audio.volume = value
                }
            }
        }

        Loader {
            anchors {
                left: parent.left
                right: parent.right
            }
            visible: active
            active: Config.options.sidebar.quickSliders.showMic
            sourceComponent: QuickSlider {
                materialSymbol: "mic"
                value: Audio.source.audio.volume
                onMoved: {
                    Audio.source.audio.volume = value
                }
            }
        }
    }

    // Slim track with its icon on the left and the value on the right.
    component QuickSlider: Item {
        id: quickSlider
        required property string materialSymbol
        property string secondaryMaterialSymbol
        // Below this fraction the slider drives `secondaryMaterialSymbol`'s setting.
        readonly property real secondaryThreshold: 0.3
        property alias value: slider.value
        property alias stopIndicatorValues: slider.stopIndicatorValues
        property string tooltipContent: `${Math.round(slider.value * 100)}%`
        signal moved()
        implicitHeight: 38

        MaterialSymbol {
            id: icon
            anchors {
                left: parent.left
                leftMargin: 4
                verticalCenter: parent.verticalCenter
            }
            iconSize: 20
            color: Appearance.colors.colOnLayer1
            text: quickSlider.secondaryMaterialSymbol.length > 0 && slider.value < quickSlider.secondaryThreshold
                ? quickSlider.secondaryMaterialSymbol : quickSlider.materialSymbol
        }
        StyledSlider {
            id: slider
            anchors {
                left: icon.right
                leftMargin: 8
                right: valueText.left
                rightMargin: 6
                verticalCenter: parent.verticalCenter
            }
            configuration: StyledSlider.Configuration.XS
            stopIndicatorValues: []
            dividerValues: quickSlider.secondaryMaterialSymbol.length > 0 ? [quickSlider.secondaryThreshold] : []
            tooltipContent: quickSlider.tooltipContent
            onMoved: quickSlider.moved()
        }
        StyledText {
            id: valueText
            anchors {
                right: parent.right
                rightMargin: 2
                verticalCenter: parent.verticalCenter
            }
            width: 44
            horizontalAlignment: Text.AlignRight
            text: quickSlider.tooltipContent
            elide: Text.ElideLeft
            font.family: Appearance.font.family.numbers
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }
    }
}
