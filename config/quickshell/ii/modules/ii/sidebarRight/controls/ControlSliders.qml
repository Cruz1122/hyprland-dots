import qs.services
import qs.modules.common
import QtQuick
import Quickshell

// Brightness, volume and microphone bars (sidebar.quickSliders).
Column {
    id: root
    readonly property var options: Config.options.sidebar.quickSliders
    property var screen: root.QsWindow.window?.screen
    property var brightnessMonitor: Brightness.getMonitorForScreen(screen)
    // The lowest part of the brightness bar dims through gamma instead.
    readonly property real gammaRange: 0.3
    readonly property bool gammaActive: Hyprsunset.gamma !== 100
    // The volume bar runs past 100% into software amplification.
    readonly property real volumeRange: 1.5
    readonly property real outputVolume: Audio.sink?.audio?.volume ?? 0

    spacing: 8
    visible: options.enable && (options.showBrightness || options.showVolume || options.showMic)

    ControlSlider {
        width: parent.width
        visible: root.options.showBrightness
        icon: root.gammaActive ? "wb_twilight" : "light_mode"
        mark: root.gammaRange
        value: !root.gammaActive
            ? root.gammaRange + (root.brightnessMonitor?.brightness ?? 0) * (1 - root.gammaRange)
            : (Hyprsunset.gamma - Hyprsunset.gammaLowerLimit) / (100 - Hyprsunset.gammaLowerLimit) * root.gammaRange
        valueText: !root.gammaActive
            ? `${Math.round((root.brightnessMonitor?.brightness ?? 0) * 100)}%`
            : `γ ${Math.round(Hyprsunset.gamma)}%`
        onMoved: newValue => {
            if (!root.brightnessMonitor)
                return;
            if (newValue >= root.gammaRange) {
                root.brightnessMonitor.setBrightness((newValue - root.gammaRange) / (1 - root.gammaRange));
                if (Hyprsunset.gamma !== 100)
                    Hyprsunset.setGamma(100);
            } else {
                if (root.brightnessMonitor.brightness !== 0)
                    root.brightnessMonitor.setBrightness(0);
                Hyprsunset.setGamma(newValue / root.gammaRange * (100 - Hyprsunset.gammaLowerLimit) + Hyprsunset.gammaLowerLimit);
            }
        }
    }
    ControlSlider {
        width: parent.width
        visible: root.options.showVolume
        icon: Audio.sink?.audio?.muted ? "volume_off" : "volume_up"
        mark: 1 / root.volumeRange
        value: root.outputVolume / root.volumeRange
        valueText: `${Math.round(root.outputVolume * 100)}%`
        onMoved: newValue => {
            if (!Audio.sink?.audio)
                return;
            const volume = newValue * root.volumeRange;
            // Sticks to 100%, so amplifying takes a deliberate push past it.
            Audio.sink.audio.volume = Math.abs(volume - 1) < 0.03 ? 1 : volume;
        }
    }
    ControlSlider {
        width: parent.width
        visible: root.options.showMic
        icon: Audio.source?.audio?.muted ? "mic_off" : "mic"
        value: Audio.source?.audio?.volume ?? 0
        onMoved: newValue => {
            if (Audio.source?.audio)
                Audio.source.audio.volume = newValue;
        }
    }
}
