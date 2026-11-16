pragma ComponentBehavior: Bound
import QtQuick
import "PosterBank.js" as Bank

// The poster of one workspace. The composition reads everything from here.
Item {
    id: root
    required property var host
    property int workspaceId: 1

    readonly property bool presenting: host.presenting
    readonly property var current: presenting ? Bank.presentation : Bank.variant(host.plan, workspaceId)
    readonly property string symbol: current.symbol
    readonly property real symbolLift: current.lift
    readonly property string term: current.term
    readonly property string text: current.text
    readonly property bool iridescent: host.iridescent
    readonly property string dateText: host.dateText
    // Sizes are drawn for a 1700 x 830 safe area and scale with the screen.
    readonly property real unit: Math.min(safeArea.width / 1700, safeArea.height / 830)

    Loader {
        id: safeArea
        // Clear of the bar, the dock and the screen edges.
        anchors {
            fill: parent
            leftMargin: 110
            rightMargin: 110
            topMargin: 120
            bottomMargin: 130
        }
        active: root.visible
        sourceComponent: PosterCenter {
            poster: root
        }
    }
}
