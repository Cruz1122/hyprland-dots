pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick

QtObject {
    readonly property real pageMargin: 20
    readonly property real pageBottomPadding: 96
    readonly property real sectionSpacing: 24
    readonly property real cardPadding: 16
    readonly property real cardSpacing: 12
    readonly property real rowSpacing: 12
    readonly property real compactRowSpacing: 8
    readonly property real controlHeight: 40
    readonly property real compactControlHeight: 36
    readonly property real iconButtonSize: 40
    readonly property real minLabelWidth: 180
    readonly property real maxContentWidth: 960
    readonly property real compactBreakpoint: 760
    readonly property real mediumBreakpoint: 900
    readonly property real cardRadius: 16
    readonly property real controlRadius: 10
    readonly property real dividerHeight: 1
    readonly property int transitionDuration: 180
}
