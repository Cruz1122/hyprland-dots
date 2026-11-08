import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Qt5Compat.GraphicalEffects
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
import qs.modules.settings.core

// Current wallpaper with the ways to change it. The path itself is owned by
// switchwall.sh (registry "managedElsewhere"), so it is only read here.
// Random anime wallpapers follow `policies.weeb` (1 = shown).
GridLayout {
    id: root

    property var row: null
    readonly property bool wide: root.width >= 560
    readonly property string wallpaper: Config.options?.background?.wallpaperPath ?? ""
    readonly property bool randomAllowed: (SettingsStore.revision, SettingsStore.value("policies.weeb") === 1)

    columns: root.wide ? 2 : 1
    columnSpacing: 16
    rowSpacing: 12

    Rectangle {
        id: frame
        Layout.preferredWidth: 320
        Layout.maximumWidth: 320
        Layout.fillWidth: !root.wide
        Layout.preferredHeight: Math.round(frame.width * 9 / 16)
        Layout.alignment: Qt.AlignTop
        radius: Appearance.rounding.normal
        color: Appearance.colors.colLayer2
        layer.enabled: true
        layer.effect: OpacityMask {
            maskSource: Rectangle {
                width: frame.width // size-ok: mask matches the frame
                height: frame.height // size-ok: mask matches the frame
                radius: frame.radius
            }
        }

        MaterialSymbol {
            anchors.centerIn: parent
            visible: preview.status !== Image.Ready
            text: "wallpaper"
            iconSize: 32
            color: Appearance.colors.colSubtext
        }

        StyledImage {
            id: preview
            anchors.fill: parent
            fillMode: Image.PreserveAspectCrop
            source: root.wallpaper.length > 0 ? root.wallpaper : ""
            cache: false
            Accessible.role: Accessible.Graphic
            Accessible.name: Translation.tr("Current wallpaper")
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignTop
        spacing: 8

        StyledText {
            Layout.fillWidth: true
            text: root.wallpaper.length > 0 ? FileUtils.trimFileProtocol(root.wallpaper) : Translation.tr("No wallpaper set")
            elide: Text.ElideMiddle
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }

        Flow {
            Layout.fillWidth: true
            spacing: 8

            SettingsButton {
                kind: "filled"
                iconName: "image_search"
                text: Translation.tr("Choose image")
                enabled: root.row?.rowEnabled ?? true
                // Without an image argument switchwall.sh asks with a file dialog.
                onClicked: Quickshell.execDetached([Directories.wallpaperSwitchScriptPath])
            }

            SettingsButton {
                visible: root.randomAllowed
                iconName: "shuffle"
                text: randomProc.running && randomProc.source === "konachan" ? Translation.tr("Downloading…") : Translation.tr("Random from Konachan")
                enabled: !randomProc.running
                onClicked: randomProc.start("konachan")
            }

            SettingsButton {
                visible: root.randomAllowed
                iconName: "shuffle"
                text: randomProc.running && randomProc.source === "osu" ? Translation.tr("Downloading…") : Translation.tr("Random osu! background")
                enabled: !randomProc.running
                onClicked: randomProc.start("osu")
            }
        }

        StyledText {
            Layout.fillWidth: true
            visible: root.randomAllowed
            text: Translation.tr("Random wallpapers are saved to Pictures/Wallpapers.")
            wrapMode: Text.Wrap
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }
    }

    // The random scripts download an image and then run switchwall.sh on it.
    Process {
        id: randomProc
        property string source: ""
        function start(name) {
            randomProc.source = name;
            randomProc.command = [`${FileUtils.trimFileProtocol(Directories.scriptPath)}/colors/random/random_${name}_wall.sh`];
            randomProc.running = true;
        }
    }
}
