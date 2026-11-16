pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.common.models.quickToggles
import QtQuick
import QtQuick.Layouts

// The configured quick toggles (sidebar.quickToggles.android.toggles) as a
// two-column grid of uniform tiles; an odd last tile spans the row.
Item {
    id: root
    signal openAudioOutputDialog()
    signal openAudioInputDialog()
    signal openBluetoothDialog()
    signal openNightLightDialog()
    signal openWifiDialog()

    readonly property var components: ({
        antiFlashbang: antiFlashbangModel,
        audio: audioModel,
        bluetooth: bluetoothModel,
        cloudflareWarp: cloudflareWarpModel,
        colorPicker: colorPickerModel,
        darkMode: darkModeModel,
        easyEffects: easyEffectsModel,
        gameMode: gameModeModel,
        idleInhibitor: idleInhibitorModel,
        mic: micModel,
        musicRecognition: musicRecognitionModel,
        network: networkModel,
        nightLight: nightLightModel,
        notifications: notificationModel,
        onScreenKeyboard: onScreenKeyboardModel,
        powerProfile: powerProfileModel,
        screenSnip: screenSnipModel
    })
    readonly property list<string> types: (Config.ready ? Config.options.sidebar.quickToggles.android.toggles : [])
        .filter(toggle => toggle && root.components[toggle.type] !== undefined)
        .map(toggle => toggle.type)

    function openMenuFor(type) {
        switch (type) {
        case "network": root.openWifiDialog(); break;
        case "bluetooth": root.openBluetoothDialog(); break;
        case "audio": root.openAudioOutputDialog(); break;
        case "mic": root.openAudioInputDialog(); break;
        case "nightLight":
        case "antiFlashbang": root.openNightLightDialog(); break;
        }
    }

    implicitHeight: grid.implicitHeight

    Component { id: antiFlashbangModel; AntiFlashbangToggle {} }
    Component { id: audioModel; AudioToggle {} }
    Component { id: bluetoothModel; BluetoothToggle {} }
    Component { id: cloudflareWarpModel; CloudflareWarpToggle {} }
    Component { id: colorPickerModel; ColorPickerToggle {} }
    Component { id: darkModeModel; DarkModeToggle {} }
    Component { id: easyEffectsModel; EasyEffectsToggle {} }
    Component { id: gameModeModel; GameModeToggle {} }
    Component { id: idleInhibitorModel; IdleInhibitorToggle {} }
    Component { id: micModel; MicToggle {} }
    Component { id: musicRecognitionModel; MusicRecognitionToggle {} }
    Component { id: networkModel; NetworkToggle {} }
    Component { id: nightLightModel; NightLightToggle {} }
    Component { id: notificationModel; NotificationToggle {} }
    Component { id: onScreenKeyboardModel; OnScreenKeyboardToggle {} }
    Component { id: powerProfileModel; PowerProfilesToggle {} }
    Component { id: screenSnipModel; ScreenSnipToggle {} }

    GridLayout {
        id: grid
        anchors {
            left: parent.left
            right: parent.right
        }
        columns: 2
        columnSpacing: 8
        rowSpacing: 8

        Repeater {
            model: root.types
            ControlTile {
                id: tile
                required property int index
                required property string modelData
                Layout.fillWidth: true
                // Equal columns whatever the label length.
                Layout.preferredWidth: 1
                Layout.columnSpan: (root.types.length % 2 === 1 && index === root.types.length - 1) ? 2 : 1
                onOpenMenu: root.openMenuFor(modelData)
                Component.onCompleted: toggleModel = root.components[modelData].createObject(tile)
            }
        }
    }
}
