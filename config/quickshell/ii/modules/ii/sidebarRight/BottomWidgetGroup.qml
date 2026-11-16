pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.common.widgets
import qs.services
// Loaded by URL below; without these imports their sibling types do not resolve.
import qs.modules.ii.sidebarRight.calendar
import qs.modules.ii.sidebarRight.todo
import qs.modules.ii.sidebarRight.pomodoro
import QtQuick

// Tools of the right rail as an accordion: three equal chips (calendar, to-do,
// timer) that open a single card underneath. Clicking the open chip closes it.
Item {
    id: root
    property int selectedTab: Persistent.states.sidebar.bottomGroup.tab
    property bool collapsed: Persistent.states.sidebar.bottomGroup.collapsed
    readonly property int pendingTasks: Todo.list.filter(task => !task.done).length
    readonly property real chipHeight: 40
    readonly property real gap: 8
    readonly property real contentHeight: 318
    // 0 = closed, 1 = open.
    property real openness: collapsed ? 0 : 1
    Behavior on openness {
        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
    }
    property var tabs: [
        {
            "name": Translation.tr("Calendar"),
            "icon": "calendar_month",
            "widget": "calendar/CalendarWidget.qml"
        },
        {
            "name": Translation.tr("To Do"),
            "icon": "done_outline",
            "widget": "todo/TodoWidget.qml"
        },
        {
            "name": Translation.tr("Timer"),
            "icon": "schedule",
            "widget": "pomodoro/PomodoroWidget.qml"
        },
    ]

    implicitHeight: chipHeight + (gap + contentHeight) * openness

    function select(index) {
        if (!root.collapsed && root.selectedTab === index) {
            Persistent.states.sidebar.bottomGroup.collapsed = true;
            return;
        }
        root.selectedTab = index;
        Persistent.states.sidebar.bottomGroup.tab = index;
        Persistent.states.sidebar.bottomGroup.collapsed = false;
    }

    Keys.onPressed: event => {
        if ((event.key === Qt.Key_PageDown || event.key === Qt.Key_PageUp) && event.modifiers === Qt.ControlModifier) {
            if (event.key === Qt.Key_PageDown) {
                root.selectedTab = Math.min(root.selectedTab + 1, root.tabs.length - 1);
            } else if (event.key === Qt.Key_PageUp) {
                root.selectedTab = Math.max(root.selectedTab - 1, 0);
            }
            event.accepted = true;
        }
    }

    Row {
        id: chips
        width: parent.width
        height: root.chipHeight
        spacing: root.gap

        Repeater {
            model: root.tabs
            RippleButton {
                id: chip
                required property int index
                required property var modelData
                readonly property bool current: !root.collapsed && root.selectedTab === index
                readonly property color ink: current ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1
                width: (chips.width - root.gap * (root.tabs.length - 1)) / root.tabs.length
                height: root.chipHeight
                buttonRadius: height / 2
                toggled: current
                colBackground: Appearance.colors.colLayer1
                onClicked: root.select(index)

                contentItem: Item {
                    Row {
                        anchors.centerIn: parent
                        spacing: 6
                        MaterialSymbol {
                            anchors.verticalCenter: parent.verticalCenter
                            text: chip.modelData.icon
                            iconSize: 18
                            fill: chip.current ? 1 : 0
                            color: chip.ink
                        }
                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: chip.index === 1 && root.pendingTasks > 0
                                ? `${chip.modelData.name} · ${root.pendingTasks}` : chip.modelData.name
                            font.pixelSize: Appearance.font.pixelSize.smallie
                            color: chip.ink
                        }
                    }
                }
            }
        }
    }

    Rectangle {
        y: root.chipHeight + root.gap * root.openness
        width: parent.width
        height: root.contentHeight * root.openness
        visible: root.openness > 0
        opacity: root.openness
        radius: Appearance.rounding.normal
        color: Appearance.colors.colLayer1
        clip: true

        Loader {
            // Fixed size: the card reveals it instead of squeezing it.
            width: parent.width
            height: root.contentHeight
            active: root.openness > 0
            source: root.tabs[root.selectedTab].widget
        }
    }
}
