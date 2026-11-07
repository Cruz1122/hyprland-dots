import qs.modules.common
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls

/**
 * Material 3 styled SpinBox component.
 */
SpinBox {
    id: root

    property real baseHeight: 35
    property real radius: Appearance.rounding.small
    property real innerButtonRadius: Appearance.rounding.unsharpen
    editable: true

    opacity: root.enabled ? 1 : 0.4

    background: Rectangle {
        color: Appearance.colors.colLayer2
        radius: root.radius
    }

    // Typed text is applied once, on Enter or focus loss: clamped to the range,
    // emitting valueModified only when the value changes. Text that is not a
    // number restores the current value, so value never becomes NaN.
    function commitTypedText() {
        const text = labelText.text.trim();
        const typed = Number(text);
        if (text.length > 0 && isFinite(typed)) {
            const next = Math.max(Math.min(root.from, root.to), Math.min(Math.max(root.from, root.to), Math.round(typed)));
            if (next !== root.value) {
                root.value = next;
                root.valueModified();
            }
        }
        labelText.text = Qt.binding(() => String(root.value));
    }

    contentItem: Item {
        implicitHeight: root.baseHeight
        implicitWidth: Math.max(labelText.implicitWidth, 40)

        StyledTextInput {
            id: labelText
            anchors.centerIn: parent
            text: String(root.value) // displayText would make the numbers weird like 1,000 instead of 1000
            color: Appearance.colors.colOnLayer2
            font.family: Appearance.font.family.numbers
            font.variableAxes: Appearance.font.variableAxes.numbers
            font.pixelSize: Appearance.font.pixelSize.small
            readOnly: !root.editable
            validator: RegularExpressionValidator { regularExpression: /-?[0-9]*/ }
            inputMethodHints: Qt.ImhFormattedNumbersOnly
            onEditingFinished: root.commitTypedText()
            Keys.onEscapePressed: labelText.text = Qt.binding(() => String(root.value))
        }
    }

    down.indicator: Rectangle {
        anchors {
            verticalCenter: parent.verticalCenter
            left: parent.left
        }
        implicitHeight: root.baseHeight
        implicitWidth: root.baseHeight
        topLeftRadius: root.radius
        bottomLeftRadius: root.radius
        topRightRadius: root.innerButtonRadius
        bottomRightRadius: root.innerButtonRadius

        color: root.down.pressed ? Appearance.colors.colLayer2Active : 
            root.down.hovered ? Appearance.colors.colLayer2Hover : 
            ColorUtils.transparentize(Appearance.colors.colLayer2)
        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        MaterialSymbol {
            anchors.centerIn: parent
            text: "remove"
            iconSize: 20
            color: Appearance.colors.colOnLayer2
        }
    }

    up.indicator: Rectangle {
        anchors {
            verticalCenter: parent.verticalCenter
            right: parent.right
        }
        implicitHeight: root.baseHeight
        implicitWidth: root.baseHeight
        topRightRadius: root.radius
        bottomRightRadius: root.radius
        topLeftRadius: root.innerButtonRadius
        bottomLeftRadius: root.innerButtonRadius

        color: root.up.pressed ? Appearance.colors.colLayer2Active : 
            root.up.hovered ? Appearance.colors.colLayer2Hover : 
            ColorUtils.transparentize(Appearance.colors.colLayer2)
        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        MaterialSymbol {
            anchors.centerIn: parent
            text: "add"
            iconSize: 20
            color: Appearance.colors.colOnLayer2
        }
    }
}
