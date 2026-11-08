import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

// Small pill on a row's label line: when a change takes effect, what it
// costs, or (interactive) the setting this row depends on, which `clicked`
// jumps to. Only interactive chips take keyboard focus (Enter or Space).
// A chip wider than maximumWidth wraps its text to a second line, so the
// name of a required setting stays readable in a narrow row.
RippleButton {
    id: root

    property string label: ""
    property string iconName: ""
    property bool interactive: false
    // Longest width before the text wraps (the label line's width).
    property real maximumWidth: 100000
    readonly property real naturalWidth: (chipIcon.visible ? chipIcon.implicitWidth + chipContent.spacing : 0) + Math.ceil(chipMetrics.advanceWidth) + 1

    implicitHeight: Math.max(22, chipContent.implicitHeight + 6)
    implicitWidth: Math.min(root.naturalWidth + 16, root.maximumWidth)
    buttonRadius: 11
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
                id: chipIcon
                visible: root.iconName.length > 0
                text: root.iconName
                iconSize: 14
                color: root.interactive ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colSubtext
            }

            StyledText {
                id: chipText
                Layout.fillWidth: true
                // Natural width: a wrapped Text's implicitWidth follows its
                // wrapped width, which would feed back into the chip's.
                Layout.preferredWidth: Math.ceil(chipMetrics.advanceWidth) + 1
                text: root.label
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: root.interactive ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colSubtext
            }
        }
    }

    TextMetrics {
        id: chipMetrics
        font: chipText.font
        text: root.label
    }

    // The whole text when even two lines cut it short (hover or keyboard focus).
    StyledToolTip {
        text: root.label
        extraVisibleCondition: chipText.truncated
        alternativeVisibleCondition: chipText.truncated && root.visualFocus
    }

    SettingsFocusRing {
        shown: root.visualFocus
        ringRadius: root.buttonRadius
    }
}
