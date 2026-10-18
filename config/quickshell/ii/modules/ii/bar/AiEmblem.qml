import qs
import qs.modules.common
import qs.services
import QtQuick
import Quickshell
import Qt5Compat.GraphicalEffects

Item {
    id: root
    readonly property var brands: [
        { name: "OpenAI", file: "openai", scale: 0.92 },
        { name: "OpenCode", file: "opencode", scale: 0.94 },
        { name: "Antigravity", file: "antigravity", scale: 1.0 },
        { name: "Zed", file: "zed", scale: 0.94 },
        { name: "Cursor", file: "cursor", scale: 0.94 },
        { name: "Claude", file: "claude", scale: 1.0 }
    ]
    property alias currentIndex: interaction.currentIndex
    readonly property bool hovered: emblemHover.hovered
    readonly property bool held: interaction.held
    readonly property string providerId: brands[currentIndex].file === "openai" ? "codex" : brands[currentIndex].file
    readonly property var quotaSnapshot: AiQuotaUsage.snapshot(providerId)
    readonly property real emblemSize: 16
    implicitWidth: Appearance.font.pixelSize.huge
    implicitHeight: implicitWidth
    Accessible.role: Accessible.Graphic
    Accessible.name: brands[currentIndex].name

    AiEmblemState {
        id: interaction
        active: root.visible
        pointerHovered: root.hovered
        brandCount: root.brands.length
    }

    HoverHandler { id: emblemHover }

    // Left click opens the AI quota panel. A child MouseArea reliably wins the
    // click over the enclosing resources MouseArea.
    // Left click opens the AI quota panel. The panel resolves its own monitor,
    // so we only pass an intent here instead of a screen name.
    MouseArea {
        objectName: "aiEmblemPanelOpener"
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            if (AiQuotaUsage.authorizationActive || AiQuotaUsage.externalBrowserSetup || AiQuotaUsage.overlayCollapsed)
                AiQuotaUsage.showAuthorizationUi();
            GlobalStates.openAiQuotaPanel("");
        }
    }

    // Layer effects only tint the SVG alpha mask; their proportions stay intact.
    Image {
        id: emblem
        anchors.centerIn: parent
        width: root.emblemSize * root.brands[root.currentIndex].scale
        height: width
        opacity: interaction.imageOpacity
        sourceSize: Qt.size(64, 64)
        fillMode: Image.PreserveAspectFit
        source: Qt.resolvedUrl("../../../assets/icons/ai/" + root.brands[root.currentIndex].file + ".svg")
        layer.enabled: true
        layer.effect: ColorOverlay {
            color: Appearance.colors.colOnLayer1
        }
    }

}
