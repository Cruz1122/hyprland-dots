import QtQuick
import Quickshell
import Quickshell.Wayland

// One layer-shell surface per output. Kept out of shell.qml so the offscreen
// snapshot, which has no layer-shell backend, never compiles PanelWindow.
Variants {
    id: root
    property string primaryName
    model: Quickshell.screens

    PanelWindow {
        required property var modelData
        screen: modelData
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "quickshell:greeter"
        WlrLayershell.keyboardFocus: modelData.name === root.primaryName ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        color: Theme.layer0

        GreeterSurface {
            anchors.fill: parent
            interactive: modelData.name === root.primaryName
        }
    }
}
