pragma Singleton

import QtQuick

// Shared spacing and size tokens of the settings app.
QtObject {
    readonly property real pageMargin: 28
    readonly property real compactPageMargin: 16
    readonly property real maxContentWidth: 880
    readonly property real sectionSpacing: 28
    readonly property real cardPadding: 6
    readonly property real rowHorizontalPadding: 16
    readonly property real rowVerticalPadding: 12
    readonly property real rowStackWidth: 520
    readonly property real controlHeight: 36
    readonly property real controlRadius: 12
    // Drop-downs share one width so a section's controls line up; long
    // labels elide.
    readonly property real selectWidth: 280
    readonly property real cardRadius: 20
    readonly property real rowRadius: 14
    readonly property real navExpandedWidth: 248
    readonly property real navCollapsedWidth: 60
    readonly property real navAutoCollapseWidth: 900
    readonly property int transitionDuration: 180
}
