import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

// Small pill on a row's label line: when a change takes effect, what it
// costs, or (interactive) the setting this row depends on, which `clicked`
// jumps to. Only interactive chips take keyboard focus (Enter or Space).
RippleButton {
    id: root

    property string label: ""
    property string iconName: ""
    property bool interactive: false
    // Longest width before the text elides (the label line's width).
    property real maximumWidth: 100000

    implicitHeight: 22
    implicitWidth: Math.min(chipContent.implicitWidth + 16, root.maximumWidth)
    buttonRadius: height / 2
    focusPolicy: root.interactive ? Qt.StrongFocus : Qt.NoFocus
    pointingHandCursor: root.interactive
    rippleEnabled: root.interactive
    colBackground: root.interactive ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer2
    colBackgroundHover: root.interactive ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colLayer2
    colRipple: Appearance.colors.colSecondaryContainerActive
    Accessible.role: root.interactive ? Accessible.Link : Accessible.StaticText
    Accessible.name: root.label
    Keys.onReturnPressed: event => {
        if (root.interactive)
            root.clicked();
        event.accepted = root.interactive;
    }
    Keys.onEnterPressed: event => {
        if (root.interactive)
            root.clicked();
        event.accepted = root.interactive;
    }

    contentItem: Item {
        implicitWidth: chipContent.implicitWidth
        implicitHeight: chipContent.implicitHeight

        RowLayout {
            id: chipContent
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4

            MaterialSymbol {
                visible: root.iconName.length > 0
                text: root.iconName
                iconSize: 14
                color: root.interactive ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colSubtext
            }

            StyledText {
                id: chipText
                Layout.fillWidth: true
                text: root.label
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: root.interactive ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colSubtext
            }
        }
    }

    // The whole text when the chip is cut short.
    StyledToolTip {
        text: root.label
        extraVisibleCondition: chipText.truncated
    }

    SettingsFocusRing {
        shown: root.visualFocus
        ringRadius: root.height / 2
    }
}
