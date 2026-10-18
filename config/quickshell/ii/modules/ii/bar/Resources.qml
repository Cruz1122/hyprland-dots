import qs.modules.common
import qs.services
import QtQuick
import QtQuick.Layouts
import "ResourcePresentation.js" as Presentation
import "AiQuotaPresentation.js" as QuotaPresentation

MouseArea {
    id: root
    property bool borderless: Config.options.bar.borderless
    property bool alwaysShowAllResources: false
    // Visibility flags are retained for API compatibility; this horizontal
    // presentation always shows the highest two available percentages.
    readonly property var topResources: Presentation.topTwo([
        { id: "RAM", icon: "memory", value: ResourceUsage.memoryUsedPercentage },
        { id: "Swap", icon: "swap_horiz", value: ResourceUsage.swapUsedPercentage,
            available: ResourceUsage.swapTotal > 0 },
        { id: "CPU", icon: "planner_review", value: ResourceUsage.cpuUsage },
        { id: "GPU", icon: "developer_board", value: ResourceUsage.gpuUsage,
            available: ResourceUsage.gpuAvailable }
    ])
    implicitWidth: rowLayout.implicitWidth + rowLayout.anchors.leftMargin + rowLayout.anchors.rightMargin
    implicitHeight: Appearance.sizes.barHeight
    hoverEnabled: !Config.options.bar.tooltips.clickToShow

    RowLayout {
        id: rowLayout

        spacing: 12
        anchors.fill: parent
        anchors.leftMargin: 4
        anchors.rightMargin: 4

        Item { Layout.fillWidth: true }

        ResourcePill {
            resource: root.topResources[0] ?? null
            Layout.alignment: Qt.AlignVCenter
        }

        AiEmblem { id: aiEmblem; Layout.alignment: Qt.AlignVCenter }

        ResourcePill {
            resource: root.topResources[1] ?? null
            Layout.alignment: Qt.AlignVCenter
        }

        Item { Layout.fillWidth: true }

    }

    Item {
        id: resourceHoverTarget
        anchors.fill: parent
        readonly property bool containsMouse: QuotaPresentation.resourceHovered(root.containsMouse, aiEmblem.hovered)
    }

    ResourcesPopup {
        hoverTarget: resourceHoverTarget
    }
}
