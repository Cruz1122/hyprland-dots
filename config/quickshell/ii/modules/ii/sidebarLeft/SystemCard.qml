import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick

// System monitor hero: one ring per resource over their shared history.
Rectangle {
    id: root
    // Fixed hues rather than theme roles: on a monochrome scheme the roles are
    // nearly identical and the three lines could not be told apart.
    readonly property color cpuColor: "#6FC3FF"
    readonly property color memoryColor: "#C4A1FF"
    readonly property color gpuColor: "#7FE0A8"

    implicitHeight: gauges.implicitHeight + history.height + 14 + 12 + 14
    radius: Appearance.rounding.normal
    color: Appearance.colors.colLayer1

    Row {
        id: gauges
        anchors {
            top: parent.top
            topMargin: 14
            horizontalCenter: parent.horizontalCenter
        }
        spacing: (root.width - 28 - 112 * visibleChildren.length) / Math.max(1, visibleChildren.length - 1)

        Gauge {
            title: "CPU"
            value: ResourceUsage.cpuUsage
            detail: ResourceUsage.cpuTemperatureAvailable ? `${ResourceUsage.cpuTemperature} °C` : " "
            accent: root.cpuColor
        }
        Gauge {
            title: Translation.tr("Memory")
            value: ResourceUsage.memoryUsedPercentage
            detail: `${(ResourceUsage.memoryUsed / (1024 * 1024)).toFixed(1)} / ${ResourceUsage.maxAvailableMemoryString}`
            accent: root.memoryColor
        }
        Gauge {
            visible: ResourceUsage.gpuAvailable
            title: "GPU"
            value: ResourceUsage.gpuUsage
            detail: `${ResourceUsage.gpuTemperature} °C`
            accent: root.gpuColor
        }
    }

    Item { // Shared history, newest sample on the right
        id: history
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
            margins: 14
        }
        height: 64

        Repeater { // Faint guides at 0, 50 and 100 %
            model: 3
            Rectangle {
                required property int index
                y: Math.round((history.height - 1) * index / 2)
                width: history.width
                height: 1
                color: Appearance.colors.colLayer2
            }
        }
        Graph {
            anchors.fill: parent
            visible: ResourceUsage.gpuAvailable
            values: ResourceUsage.gpuUsageHistory
            points: ResourceUsage.historyLength
            alignment: Graph.Alignment.Right
            color: root.gpuColor
            fillOpacity: 0
        }
        Graph {
            anchors.fill: parent
            values: ResourceUsage.memoryUsageHistory
            points: ResourceUsage.historyLength
            alignment: Graph.Alignment.Right
            color: root.memoryColor
            fillOpacity: 0
        }
        Graph {
            anchors.fill: parent
            values: ResourceUsage.cpuUsageHistory
            points: ResourceUsage.historyLength
            alignment: Graph.Alignment.Right
            color: root.cpuColor
            fillOpacity: 0.18
        }
    }
}
