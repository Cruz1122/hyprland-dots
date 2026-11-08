import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

// Text button with an optional leading icon.
// kind: "tonal" (default), "filled", "danger", "text".
RippleButton {
    id: root

    property string kind: "tonal"
    property string iconName: ""
    readonly property color foreground: root.kind === "filled" ? Appearance.colors.colOnPrimary
        : root.kind === "danger" ? Appearance.colors.colOnError
        : root.kind === "text" ? Appearance.colors.colPrimary
        : Appearance.colors.colOnSecondaryContainer

    implicitHeight: SettingsMetrics.controlHeight
    implicitWidth: content.implicitWidth + (root.kind === "text" ? 24 : 32)
    buttonRadius: height / 2
    colBackground: root.kind === "filled" ? Appearance.colors.colPrimary
        : root.kind === "danger" ? Appearance.colors.colError
        : root.kind === "text" ? "transparent"
        : Appearance.colors.colSecondaryContainer
    colBackgroundHover: root.kind === "filled" ? Appearance.colors.colPrimaryHover
        : root.kind === "danger" ? Appearance.colors.colErrorHover
        : root.kind === "text" ? Appearance.colors.colLayer1Hover
        : Appearance.colors.colSecondaryContainerHover
    colRipple: root.kind === "filled" ? Appearance.colors.colPrimaryActive
        : root.kind === "danger" ? Appearance.colors.colErrorActive
        : root.kind === "text" ? Appearance.colors.colLayer1Active
        : Appearance.colors.colSecondaryContainerActive
    Accessible.name: root.text
    Accessible.role: Accessible.Button

    contentItem: Item {
        implicitWidth: content.implicitWidth
        implicitHeight: content.implicitHeight

        RowLayout {
            id: content
            anchors.centerIn: parent
            spacing: 8

            MaterialSymbol {
                visible: root.iconName.length > 0
                text: root.iconName
                iconSize: 18
                color: root.foreground
            }

            StyledText {
                text: root.text
                color: root.foreground
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.Medium
            }
        }
    }

    SettingsFocusRing {
        shown: root.visualFocus
        ringRadius: root.height / 2
    }
}
