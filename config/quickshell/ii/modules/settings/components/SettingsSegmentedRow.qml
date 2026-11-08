import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import "../core/SettingsLogic.js" as Logic

// Segmented buttons for enums with a few short options. Left/Right move
// the selection when a segment has keyboard focus.
SettingsRow {
    id: row

    readonly property var options: (row.entry?.options ?? []).map(o => ({
        value: o.value,
        label: Translation.tr(String(o.label ?? o.value)),
        icon: o.icon ?? ""
    }))
    readonly property int currentIndex: row.options.findIndex(o => Logic.deepEqual(o.value, row.value))
    property int focusedIndex: -1

    focusVisible: false
    interactHandler: () => {
        if (row.options.length < 2)
            return false;
        return row.select((Math.max(0, row.currentIndex) + 1) % row.options.length);
    }

    function select(index) {
        if (index < 0 || index >= row.options.length)
            return false;
        return row.commit(row.options[index].value);
    }

    Rectangle {
        id: track
        implicitWidth: segments.implicitWidth + 6
        implicitHeight: segments.implicitHeight + 6
        radius: height / 2
        color: Appearance.colors.colLayer2
        border.width: 1
        border.color: Appearance.colors.colOutlineVariant

        RowLayout {
            id: segments
            anchors.centerIn: parent
            spacing: 2

            Repeater {
                model: row.options

                delegate: RippleButton {
                    id: segment
                    required property var modelData
                    required property int index
                    readonly property bool selected: segment.index === row.currentIndex

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
                    onClicked: row.select(segment.index)
                    Keys.onLeftPressed: row.select(segment.index - 1) && segments.children[segment.index - 1]?.forceActiveFocus()
                    Keys.onRightPressed: row.select(segment.index + 1) && segments.children[segment.index + 1]?.forceActiveFocus()

                    contentItem: Item {
                        implicitWidth: segmentContent.implicitWidth
                        implicitHeight: segmentContent.implicitHeight

                        RowLayout {
                            id: segmentContent
                            anchors.centerIn: parent
                            spacing: 6

                            MaterialSymbol {
                                visible: segment.selected || segment.modelData.icon.length > 0
                                text: segment.selected ? "check" : segment.modelData.icon
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
}
