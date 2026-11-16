import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.sidebarRight.controls
import QtQuick
import QtQuick.Layouts
import Quickshell

// Eye-protection page of the right rail: night light, anti-flashbang,
// brightness and gamma.
RailPage {
    id: root
    title: Translation.tr("Eye protection")

    property var screen: root.QsWindow.window?.screen
    property var brightnessMonitor: Brightness.getMonitorForScreen(screen)
    // Night light range in kelvin: the bar grows as the light gets warmer.
    readonly property real coolest: 6500
    readonly property real warmest: 1200
    readonly property real gammaFloor: Hyprsunset.gammaLowerLimit / 100

    StyledFlickable {
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        contentHeight: list.implicitHeight

        Column {
            id: list
            width: parent.width
            spacing: 6

            RailSection {
                text: Translation.tr("Night Light")
            }
            RailRow {
                width: parent.width
                interactive: true
                highlighted: Hyprsunset.temperatureActive
                icon: "nightlight"
                title: Translation.tr("Enable now")
                onClicked: Hyprsunset.toggleTemperature(!Hyprsunset.temperatureActive)
                StyledSwitch {
                    anchors.verticalCenter: parent.verticalCenter
                    checked: Hyprsunset.temperatureActive
                    onToggled: Hyprsunset.toggleTemperature(checked)
                }
            }
            RailRow {
                width: parent.width
                interactive: true
                highlighted: Config.options.light.night.automatic
                icon: "night_sight_auto"
                title: Translation.tr("Automatic")
                subtitle: `${Hyprsunset.from} – ${Hyprsunset.to}`
                onClicked: Config.options.light.night.automatic = !Config.options.light.night.automatic
                StyledSwitch {
                    anchors.verticalCenter: parent.verticalCenter
                    checked: Config.options.light.night.automatic
                    onToggled: Config.options.light.night.automatic = checked
                }
            }
            ControlSlider {
                width: parent.width
                icon: "thermostat"
                value: (root.coolest - Config.options.light.night.colorTemperature) / (root.coolest - root.warmest)
                valueText: `${Math.round(Config.options.light.night.colorTemperature)} K`
                onMoved: newValue => Config.options.light.night.colorTemperature = Math.round(root.coolest - newValue * (root.coolest - root.warmest))
            }

            RailSection {
                text: Translation.tr("Anti-flashbang (experimental)")
            }
            RailRow {
                id: shaderRow
                width: parent.width
                interactive: true
                highlighted: HyprlandAntiFlashbangShader.enabled
                icon: "filter"
                title: Translation.tr("Content adjustment")
                subtitle: Translation.tr("Dims bright content with a screen shader")
                function apply(enabled) {
                    if (enabled)
                        HyprlandAntiFlashbangShader.enable();
                    else
                        HyprlandAntiFlashbangShader.disable();
                }
                onClicked: apply(!HyprlandAntiFlashbangShader.enabled)
                StyledSwitch {
                    anchors.verticalCenter: parent.verticalCenter
                    checked: HyprlandAntiFlashbangShader.enabled
                    onToggled: shaderRow.apply(checked)
                }
            }
            RailRow {
                width: parent.width
                interactive: true
                highlighted: Config.options.light.antiFlashbang.enable
                icon: "light_mode"
                title: Translation.tr("Brightness adjustment")
                subtitle: Translation.tr("Lowers the display brightness on bright windows")
                onClicked: Config.options.light.antiFlashbang.enable = !Config.options.light.antiFlashbang.enable
                StyledSwitch {
                    anchors.verticalCenter: parent.verticalCenter
                    checked: Config.options.light.antiFlashbang.enable
                    onToggled: Config.options.light.antiFlashbang.enable = checked
                }
            }

            RailSection {
                text: Translation.tr("Brightness")
            }
            ControlSlider {
                width: parent.width
                icon: "light_mode"
                value: root.brightnessMonitor?.brightness ?? 0
                onMoved: newValue => root.brightnessMonitor?.setBrightness(newValue)
            }

            RailSection {
                text: Translation.tr("Gamma")
            }
            ControlSlider {
                width: parent.width
                icon: "contrast"
                value: (Hyprsunset.gamma / 100 - root.gammaFloor) / (1 - root.gammaFloor)
                valueText: `${Math.round(Hyprsunset.gamma)}%`
                onMoved: newValue => Hyprsunset.setGamma((root.gammaFloor + newValue * (1 - root.gammaFloor)) * 100)
            }
        }
    }
}
