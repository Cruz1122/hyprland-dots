import qs.modules.common
import qs.modules.common.widgets
import QtQuick

// Compact pill button for rail pages: tonal by default, filled when `primary`.
RippleButton {
    id: root
    property string label: ""
    // Material symbol name (`icon` is taken by Button).
    property string symbol: ""
    property bool primary: false
    readonly property color ink: !enabled ? Appearance.colors.colSubtext
        : primary ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1

    implicitHeight: 32
    implicitWidth: row.implicitWidth + (label.length > 0 ? 26 : 14)
    buttonRadius: height / 2
    colBackground: primary ? Appearance.colors.colPrimary : Appearance.colors.colLayer2
    colBackgroundHover: primary ? Appearance.colors.colPrimaryHover : Appearance.colors.colLayer2Hover
    colRipple: primary ? Appearance.colors.colPrimaryActive : Appearance.colors.colLayer2Active
    opacity: enabled ? 1 : 0.6

    contentItem: Item {
        Row {
            id: row
            anchors.centerIn: parent
            spacing: 5
            MaterialSymbol {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.symbol.length > 0
                text: root.symbol
                iconSize: 18
                color: root.ink
            }
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.label.length > 0
                text: root.label
                font.pixelSize: Appearance.font.pixelSize.smallie
                color: root.ink
            }
        }
    }
}
