import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs.modules.settings.core
import "CurveMath.js" as CurveMath
import "AnimationsPageLogic.js" as PageLogic

// The user's curves (widget "curveLibrary", key animation.curves; docs/
// settings.md "Animations page"): thumbnails with their name and the cards
// that use them, an editor to add or change one (name plus
// SettingsCurveEditor with "Start from…") and delete, which is refused while
// a card uses the curve. The value is the whole list; every change writes it
// with SettingsStore.write. Names (ii_curve_N) are generated, never typed:
// the user only names the label.
SettingsRow {
    id: row

    readonly property var backend: SettingsStore.backends?.animation ?? null
    readonly property var curves: Array.isArray(row.value) ? row.value : []
    readonly property var catalog: {
        void SettingsStore.revision;
        return row.backend?.curveCatalog() ?? [];
    }
    readonly property var baseCurves: row.catalog.filter(c => c.type === "bezier")
    // Curve being edited: { name, isNew, original, spring, source } or null.
    // A spring (only from a hand-edited or imported config: the editor
    // makes beziers) keeps its mass/stiffness/damping; only its name changes.
    property var editing: null
    property string editLabel: ""
    property var editPoints: CurveMath.DEFAULT_POINTS
    readonly property string labelProblem: row.editing ? PageLogic.labelProblem(row.editLabel) : ""
    property string refusal: ""

    stacked: true
    controlFillsWidth: true
    needsValue: true
    interactHandler: () => false

    // Card ids that use a curve, as "Section › Card" labels.
    function usageLabels(name) {
        void SettingsStore.revision;
        const ids = row.backend?.curveUsage(name) ?? [];
        return ids.map(id => {
            const entry = SettingsRegistry.entry(`animation.${id}`);
            if (!entry)
                return id;
            const section = SettingsRegistry.section(entry.pageId, entry.section);
            return section ? `${Translation.tr(section.title)} › ${Translation.tr(entry.label)}` : Translation.tr(entry.label);
        });
    }

    function startAdd() {
        const name = PageLogic.newCurveName(row.catalog.map(c => c.name));
        row.refusal = "";
        row.editing = { name: name, isNew: true };
        row.editLabel = Translation.tr("My curve %1").arg(name.slice(PageLogic.USER_CURVE_PREFIX.length));
        row.editPoints = CurveMath.DEFAULT_POINTS.slice();
    }

    function startEdit(curve) {
        row.refusal = "";
        const spring = curve.type === "spring";
        row.editing = { name: curve.name, isNew: false, spring: spring, source: curve,
            original: spring ? null : (curve.points ?? CurveMath.DEFAULT_POINTS).slice() };
        row.editLabel = String(curve.label ?? curve.name);
        row.editPoints = (curve.points ?? CurveMath.DEFAULT_POINTS).slice();
    }

    function cancelEdit() {
        row.editing = null;
    }

    function save(points) {
        if (!row.editing || row.labelProblem.length > 0)
            return false;
        const desc = row.editing.spring ? Object.assign({}, row.editing.source, { label: row.editLabel })
            : { type: "bezier", label: row.editLabel, points: points };
        if (!row.commit(PageLogic.curvesWith(row.curves, row.editing.name, desc)))
            return false;
        row.editing = null;
        return true;
    }

    // Refused while a card uses the curve: the user picks another curve there first.
    function deleteCurve(name) {
        const users = row.usageLabels(name);
        if (users.length > 0) {
            row.refusal = Translation.tr("“%1” cannot be deleted while a card uses it: %2").arg(row.curves.find(c => c.name === name)?.label ?? name).arg(users.join(", "));
            return false;
        }
        row.refusal = "";
        if (row.editing?.name === name)
            row.editing = null;
        return row.commit(PageLogic.curvesWith(row.curves, name, null));
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 12

        StyledText {
            objectName: "curveLibraryEmpty"
            visible: row.curves.length === 0 && !row.editing
            Layout.fillWidth: true
            text: Translation.tr("You have no curves yet. Add one to start from a curve you like and change it.")
            wrapMode: Text.Wrap
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }

        Repeater {
            model: row.curves

            delegate: RowLayout {
                id: curveItem
                required property var modelData
                readonly property var users: row.usageLabels(curveItem.modelData.name)

                objectName: "userCurve:" + curveItem.modelData.name
                Layout.fillWidth: true
                spacing: 12

                SettingsCurveThumb {
                    Layout.alignment: Qt.AlignTop
                    implicitWidth: 72
                    implicitHeight: 54
                    curve: curveItem.modelData
                    selected: row.editing?.name === curveItem.modelData.name
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 2

                    StyledText {
                        Layout.fillWidth: true
                        // The user's own text: never markup.
                        textFormat: Text.PlainText
                        text: String(curveItem.modelData.label ?? curveItem.modelData.name)
                        elide: Text.ElideRight
                        color: Appearance.colors.colOnLayer1
                    }

                    StyledText {
                        objectName: "curveUsage"
                        Layout.fillWidth: true
                        text: curveItem.users.length > 0 ? Translation.tr("Used by: %1").arg(curveItem.users.join(", ")) : Translation.tr("Not used by any card")
                        wrapMode: Text.Wrap
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }
                }

                SettingsIconButton {
                    objectName: "editCurve"
                    iconName: "edit"
                    tooltip: (curveItem.modelData.type === "spring" ? Translation.tr("Rename “%1”") : Translation.tr("Edit “%1”")).arg(String(curveItem.modelData.label ?? curveItem.modelData.name))
                    onClicked: row.startEdit(curveItem.modelData)
                }

                SettingsIconButton {
                    objectName: "deleteCurve"
                    iconName: "delete"
                    tooltip: Translation.tr("Delete “%1”").arg(String(curveItem.modelData.label ?? curveItem.modelData.name))
                    onClicked: row.deleteCurve(curveItem.modelData.name)
                }
            }
        }

        StyledText {
            objectName: "curveRefusal"
            visible: row.refusal.length > 0
            Layout.fillWidth: true
            textFormat: Text.PlainText
            text: row.refusal
            wrapMode: Text.Wrap
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colError
        }

        SettingsButton {
            objectName: "addCurve"
            visible: !row.editing
            iconName: "add"
            text: Translation.tr("Add a curve")
            onClicked: row.startAdd()
        }

        // Editor of a new or existing curve.
        Rectangle {
            objectName: "curveEditorPanel"
            visible: row.editing !== null
            Layout.fillWidth: true
            implicitHeight: editorLayout.implicitHeight + 28
            radius: SettingsMetrics.cardRadius - 6
            color: Appearance.colors.colLayer2

            ColumnLayout {
                id: editorLayout
                anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                    margins: 14
                }
                spacing: 12

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    StyledText {
                        text: Translation.tr("Name")
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.Medium
                        color: Appearance.colors.colOnLayer2
                    }

                    SettingsTextField {
                        id: labelField
                        objectName: "curveLabelField"
                        Layout.fillWidth: true
                        Layout.maximumWidth: SettingsMetrics.selectWidth
                        invalid: row.labelProblem.length > 0
                        maximumLength: 40
                        Accessible.name: Translation.tr("Name")
                        onTextEdited: row.editLabel = labelField.text
                    }

                    Binding {
                        target: labelField
                        property: "text"
                        value: row.editLabel
                        restoreMode: Binding.RestoreNone
                    }

                    StyledText {
                        visible: row.labelProblem.length > 0
                        Layout.fillWidth: true
                        text: Translation.tr(row.labelProblem)
                        wrapMode: Text.Wrap
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colError
                    }
                }

                StyledText {
                    objectName: "curveSpringNote"
                    visible: row.editing?.spring === true
                    Layout.fillWidth: true
                    text: Translation.tr("Springs are not edited here: you can only change the name.")
                    wrapMode: Text.Wrap
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }

                SettingsCurveEditor {
                    id: editor
                    objectName: "curveEditor"
                    visible: row.editing?.spring !== true
                    Layout.fillWidth: true
                    points: row.editPoints
                    originalPoints: row.editing?.original ?? null
                    baseCurves: row.baseCurves
                    durationMs: 500
                }

                RowLayout {
                    Layout.alignment: Qt.AlignRight
                    spacing: 8

                    SettingsButton {
                        objectName: "cancelCurve"
                        kind: "text"
                        text: Translation.tr("Cancel")
                        onClicked: row.cancelEdit()
                    }

                    SettingsButton {
                        objectName: "saveCurve"
                        kind: "filled"
                        iconName: "check"
                        text: Translation.tr("Save")
                        enabled: row.labelProblem.length === 0
                        onClicked: row.save(editor.editedPoints)
                    }
                }
            }
        }
    }
}
