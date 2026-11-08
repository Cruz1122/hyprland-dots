import QtQuick
import qs.modules.common
import qs.modules.common.widgets
import qs.services

// Radio group of curve thumbnails. `curves` are curve descriptors with
// `label` (an English source string, translated here; "user" curves show
// their own label). `value` is the selected curve name; when it is not in
// the list an extra "Not recognized: <name>" item stands for it, so the value
// is shown and kept. Choosing a curve emits activated(name); the picker
// never changes `value` itself.
//
// Keyboard: the group is one Tab stop; arrows move between curves, Home/End
// jump to the ends, Space/Enter choose the focused curve.
FocusScope {
    id: root

    property var curves: []
    property string value: ""
    property string accessibleName: ""
    property real itemWidth: 116
    readonly property int knownIndex: root.curves.findIndex(c => c?.name === root.value)
    readonly property bool unrecognized: root.value.length > 0 && root.knownIndex < 0
    readonly property var items: root.unrecognized ? root.curves.concat([{ name: root.value, unrecognized: true }]) : root.curves
    readonly property int selectedIndex: root.unrecognized ? root.items.length - 1 : root.knownIndex
    property int focusIndex: 0
    // Focus rings only after keyboard use, like the controls' visualFocus.
    property bool keyboardFocus: false

    signal activated(string name)

    function labelFor(item) {
        if (item?.unrecognized)
            return Translation.tr("Not recognized: %1").arg(item.name);
        const label = String(item?.label ?? item?.name ?? "");
        return item?.group === "user" ? label : Translation.tr(label);
    }

    function moveFocus(index) {
        if (root.items.length === 0)
            return;
        root.focusIndex = Math.max(0, Math.min(root.items.length - 1, index));
    }

    function choose(index) {
        const item = root.items[index];
        if (!item || !root.enabled)
            return;
        root.focusIndex = index;
        // Choosing the unrecognized entry keeps the current value as it is.
        if (!item.unrecognized)
            root.activated(item.name);
    }

    implicitWidth: root.itemWidth * 3 + flow.spacing * 2
    implicitHeight: flow.implicitHeight
    activeFocusOnTab: true
    opacity: root.enabled ? 1 : 0.6
    Accessible.role: Accessible.Grouping
    Accessible.name: root.accessibleName

    onActiveFocusChanged: {
        if (root.activeFocus)
            root.moveFocus(root.selectedIndex >= 0 ? root.selectedIndex : 0);
        else
            root.keyboardFocus = false;
    }
    onItemsChanged: root.moveFocus(root.focusIndex)

    Keys.onPressed: event => {
        let handled = true;
        switch (event.key) {
        case Qt.Key_Left:
        case Qt.Key_Up:
            root.moveFocus(root.focusIndex - 1);
            break;
        case Qt.Key_Right:
        case Qt.Key_Down:
            root.moveFocus(root.focusIndex + 1);
            break;
        case Qt.Key_Home:
            root.moveFocus(0);
            break;
        case Qt.Key_End:
            root.moveFocus(root.items.length - 1);
            break;
        case Qt.Key_Space:
        case Qt.Key_Return:
        case Qt.Key_Enter:
            root.choose(root.focusIndex);
            break;
        default:
            handled = false;
        }
        if (handled)
            root.keyboardFocus = true;
        event.accepted = handled;
    }
    // Tab and Backtab reach the scope first; a focus change by keyboard
    // shows the ring.
    Keys.onReleased: event => {
        if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab)
            root.keyboardFocus = true;
    }

    Flow {
        id: flow
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 8

        Repeater {
            model: root.items

            delegate: Item {
                id: option
                required property var modelData
                required property int index
                readonly property bool checked: option.index === root.selectedIndex
                readonly property bool current: root.activeFocus && option.index === root.focusIndex

                objectName: "curveOption:" + option.modelData.name
                implicitWidth: root.itemWidth
                implicitHeight: column.implicitHeight
                Accessible.role: Accessible.RadioButton
                Accessible.name: root.labelFor(option.modelData)
                Accessible.checkable: true
                Accessible.checked: option.checked
                Accessible.focusable: true
                Accessible.focused: option.current
                Accessible.onPressAction: root.choose(option.index)

                Column {
                    id: column
                    anchors.left: parent.left
                    anchors.right: parent.right
                    spacing: 6

                    SettingsCurveThumb {
                        id: thumb
                        anchors.left: parent.left
                        anchors.right: parent.right
                        curve: option.modelData.unrecognized ? null : option.modelData
                        selected: option.checked
                        enabled: root.enabled
                        focusShown: option.current && root.keyboardFocus
                    }

                    StyledText {
                        objectName: "curveLabel:" + option.modelData.name
                        anchors.left: parent.left
                        anchors.right: parent.right
                        // Labels and unknown names come from the user's config:
                        // show them literally, never as markup.
                        textFormat: Text.PlainText
                        text: root.labelFor(option.modelData)
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                        maximumLineCount: option.modelData.unrecognized ? 3 : 2
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: option.checked ? Font.Medium : Font.Normal
                        color: option.checked ? Appearance.colors.colOnLayer1 : Appearance.colors.colSubtext
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: root.enabled
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.keyboardFocus = false;
                        root.forceActiveFocus(Qt.MouseFocusReason);
                        root.choose(option.index);
                    }
                }
            }
        }
    }
}
