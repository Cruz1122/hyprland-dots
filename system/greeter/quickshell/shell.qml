//@ pragma UseQApplication
import QtQuick
import Quickshell

// Login screen run by greetd inside a minimal Hyprland (see ../hyprland.lua).
//
// Preview without greetd:
//   GREETER_THEME_DIR=<snapshot> qs -p system/greeter/quickshell
// Add GREETER_SNAPSHOT=<file.png> to render one frame offscreen and exit,
// without opening anything on the screens.
ShellRoot {
    id: root

    readonly property string snapshotPath: Quickshell.env("GREETER_SNAPSHOT") || ""

    // The login card goes on one screen: GREETER_PRIMARY, else the laptop
    // panel, else the first output.
    readonly property string primaryName: {
        const wanted = Quickshell.env("GREETER_PRIMARY");
        const screens = Quickshell.screens;
        if (wanted && screens.some(s => s.name === wanted))
            return wanted;
        const panel = screens.find(s => s.name.startsWith("eDP"));
        return (panel ?? screens[0])?.name ?? "";
    }

    Loader {
        active: root.snapshotPath.length === 0
        source: "Screens.qml"
        onLoaded: item.primaryName = Qt.binding(() => root.primaryName)
    }

    Loader { // Offscreen snapshot for previews
        active: root.snapshotPath.length > 0
        sourceComponent: FloatingWindow {
            implicitWidth: 1920
            implicitHeight: 1080
            color: Theme.layer0

            GreeterSurface {
                id: surface
                // Fixed size: the compositor may tile the window smaller.
                width: 1920
                height: 1080
                interactive: true
            }
            Timer { // Let fonts, images and the entrance animation settle
                running: true
                interval: Number(Quickshell.env("GREETER_SNAPSHOT_DELAY") || 1800)
                onTriggered: surface.grabToImage(result => {
                    if (!result.saveToFile(root.snapshotPath))
                        console.warn(`greeter: could not write ${root.snapshotPath}`);
                    Qt.quit();
                })
            }
        }
    }
}
