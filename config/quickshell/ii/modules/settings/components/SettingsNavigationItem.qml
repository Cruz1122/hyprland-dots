import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

// One page in the navigation. Collapsed, it shows only the icon and the
// page title as a hover tooltip.
RippleButton {
    id: root

    property var page: null
    property bool expanded: true
    property bool selected: false
    readonly property string title: Translation.tr(root.page?.title ?? "")

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

            MaterialSymbol {
                text: root.page?.icon ?? "settings"
                rotation: root.page?.iconRotation ?? 0
                iconSize: 22
                fill: root.selected ? 1 : 0
                color: root.selected ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnSurfaceVariant
            }

            StyledText {
                visible: root.expanded
                Layout.fillWidth: true
                text: root.title
                elide: Text.ElideRight
                font.weight: root.selected ? Font.DemiBold : Font.Normal
                color: root.selected ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnSurfaceVariant
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
