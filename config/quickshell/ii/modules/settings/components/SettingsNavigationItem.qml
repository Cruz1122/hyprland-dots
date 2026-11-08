import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs.modules.settings.core

// One page in the navigation. Collapsed, it shows only the icon and the
// page title as a hover tooltip. A small count shows how many settings of
// the page are changed (hidden at 0; its width stays reserved so the list
// does not shift); collapsed, a dot on the icon.
RippleButton {
    id: root

    property var page: null
    property bool expanded: true
    property bool selected: false
    readonly property string title: Translation.tr(root.page?.title ?? "")
    readonly property int modifiedCount: {
        void SettingsStore.revision;
        return root.page ? SettingsStore.modifiedCount(root.page.id) : 0;
    }

    objectName: "nav:" + (root.page?.id ?? "")
    implicitHeight: 40
    implicitWidth: root.expanded ? content.implicitWidth + 32 : 44
    buttonRadius: height / 2
    toggled: root.selected
    colBackground: "transparent"
    colBackgroundHover: Appearance.colors.colLayer1Hover
    colBackgroundToggled: Appearance.colors.colSecondaryContainer
    colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
    colRipple: Appearance.colors.colLayer1Active
    colRippleToggled: Appearance.colors.colSecondaryContainerActive
    Accessible.name: root.title
    Accessible.description: root.modifiedCount > 0 ? Translation.tr("Changed settings: %1").arg(root.modifiedCount) : ""
    Accessible.role: Accessible.PageTab
    Accessible.selected: root.selected

    contentItem: Item {
        implicitWidth: content.implicitWidth
        implicitHeight: content.implicitHeight

        RowLayout {
            id: content
            anchors.verticalCenter: parent.verticalCenter
            x: root.expanded ? 4 : (parent.width - width) / 2
            width: root.expanded ? parent.width - 4 : implicitWidth // size-ok: content of a button, not in a layout
            spacing: 14

            Item {
                implicitWidth: pageIcon.implicitWidth
                implicitHeight: pageIcon.implicitHeight

                MaterialSymbol {
                    id: pageIcon
                    anchors.centerIn: parent
                    text: root.page?.icon ?? "settings"
                    rotation: root.page?.iconRotation ?? 0
                    iconSize: 22
                    fill: root.selected ? 1 : 0
                    color: root.selected ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnSurfaceVariant
                }

                // Outside the icon, so a rotated icon does not move it.
                Rectangle {
                    visible: !root.expanded && root.modifiedCount > 0
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.rightMargin: -3
                    anchors.topMargin: -1
                    implicitWidth: 8
                    implicitHeight: 8
                    radius: 4
                    color: Appearance.colors.colPrimary
                }
            }

            StyledText {
                visible: root.expanded
                Layout.fillWidth: true
                text: root.title
                elide: Text.ElideRight
                font.weight: root.selected ? Font.DemiBold : Font.Normal
                color: root.selected ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnSurfaceVariant
            }

            // Changed settings on the page; the width is reserved at 0.
            StyledText {
                objectName: "modifiedCount"
                visible: root.expanded
                opacity: root.modifiedCount > 0 ? 1 : 0
                Layout.preferredWidth: countMetrics.width + 4
                Layout.rightMargin: 8
                horizontalAlignment: Text.AlignRight
                text: root.modifiedCount > 0 ? String(root.modifiedCount) : ""
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.family: Appearance.font.family.numbers
                font.variableAxes: Appearance.font.variableAxes.numbers
                color: root.selected ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colPrimary
                Accessible.ignored: true
            }

            TextMetrics {
                id: countMetrics
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.family: Appearance.font.family.numbers
                text: "99"
            }
        }
    }

    StyledToolTip {
        text: root.title
        extraVisibleCondition: !root.expanded
    }

    SettingsFocusRing {
        shown: root.visualFocus
        ringRadius: root.height / 2
    }
}
