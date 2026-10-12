import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

RippleButton {
    id: root

    property string label: ""
    property string mainText: ""
    property string nerdIcon: ""
    property bool materialIconFill: true
    property string materialIcon: ""
    property Component mainContentComponent: Component {
        StyledText {
            visible: text.length > 0
            text: root.label || root.mainText
            font.pixelSize: Appearance.font.pixelSize.small
            color: root.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
        }
    }
    property real iconRotation: 0
    property bool outlined: false

    buttonText: root.label
    buttonRadius: SettingsMetrics.controlRadius
    height: SettingsMetrics.controlHeight
    Accessible.name: root.label

    contentItem: RowLayout {
        spacing: 8

        Item {
            Layout.fillWidth: false
            implicitWidth: Math.max(materialIconLoader.implicitWidth, nerdIconLoader.implicitWidth)
            implicitHeight: Math.max(materialIconLoader.implicitHeight, nerdIconLoader.implicitHeight)

            Loader {
                id: materialIconLoader
                anchors.centerIn: parent
                active: root.materialIcon.length > 0 && root.nerdIcon.length === 0
                sourceComponent: MaterialSymbol {
                    text: root.materialIcon
                    iconSize: Appearance.font.pixelSize.large
                    rotation: root.iconRotation
                    fill: root.materialIconFill ? 1 : 0
                    color: root.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
                }
            }

            Loader {
                id: nerdIconLoader
                anchors.centerIn: parent
                active: root.nerdIcon.length > 0
                sourceComponent: StyledText {
                    text: root.nerdIcon
                    font.family: Appearance.font.family.iconNerd
                    font.pixelSize: Appearance.font.pixelSize.large
                    color: root.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
                }
            }
        }

        Loader {
            Layout.fillWidth: true
            sourceComponent: root.mainContentComponent
        }
    }

    colBackground: root.outlined ? "transparent" : Appearance.colors.colLayer1
    colBackgroundHover: Appearance.colors.colLayer2Hover
}
