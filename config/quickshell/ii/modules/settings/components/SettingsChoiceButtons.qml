import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import "../core/SettingsLogic.js" as Logic

// Segmented buttons for custom delegates whose value is not a single
// stored key (light/dark mode, bar position). `options` are
// { value, label, icon } with translated labels; `chosen` fires on click.
Rectangle {
    id: root

    property var options: []
    property var currentValue: undefined
    property string accessibleName: ""
    readonly property int currentIndex: root.options.findIndex(o => Logic.deepEqual(o.value, root.currentValue))

    signal chosen(var value)

    implicitWidth: segments.implicitWidth + 6
    implicitHeight: segments.implicitHeight + 6
    radius: height / 2
    color: Appearance.colors.colLayer2
    border.width: 1
    border.color: Appearance.colors.colOutlineVariant
    opacity: root.enabled ? 1 : 0.5
    Accessible.role: Accessible.Grouping
    Accessible.name: root.accessibleName

    function select(index) {
        if (index < 0 || index >= root.options.length)
            return false;
        root.chosen(root.options[index].value);
        return true;
    }

    RowLayout {
        id: segments
        anchors.centerIn: parent
        spacing: 2

        Repeater {
            model: root.options

            delegate: RippleButton {
                id: segment
                required property var modelData
                required property int index
                readonly property bool selected: segment.index === root.currentIndex

                implicitHeight: SettingsMetrics.controlHeight - 4
                implicitWidth: segmentContent.implicitWidth + 28
                buttonRadius: height / 2
                toggled: segment.selected
                colBackground: "transparent"
                colBackgroundHover: Appearance.colors.colLayer2Hover
                colBackgroundToggled: Appearance.colors.colSecondaryContainer
                colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
                colRipple: Appearance.colors.colLayer2Active
                colRippleToggled: Appearance.colors.colSecondaryContainerActive
                Accessible.name: segment.modelData.label
                Accessible.role: Accessible.RadioButton
                Accessible.checked: segment.selected
                onClicked: root.select(segment.index)
                Keys.onLeftPressed: root.select(segment.index - 1) && segments.children[segment.index - 1]?.forceActiveFocus()
                Keys.onRightPressed: root.select(segment.index + 1) && segments.children[segment.index + 1]?.forceActiveFocus()

                contentItem: Item {
                    implicitWidth: segmentContent.implicitWidth
                    implicitHeight: segmentContent.implicitHeight

                    RowLayout {
                        id: segmentContent
                        anchors.centerIn: parent
                        spacing: 6

                        MaterialSymbol {
                            visible: text.length > 0
                            text: segment.selected ? "check" : (segment.modelData.icon ?? "")
                            iconSize: 16
                            color: segment.selected ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer2
                        }

                        StyledText {
                            text: segment.modelData.label
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: segment.selected ? Font.Medium : Font.Normal
                            color: segment.selected ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer2
                        }
                    }
                }

                SettingsFocusRing {
                    shown: segment.visualFocus
                    ringRadius: segment.height / 2
                }
            }
        }
    }
}
