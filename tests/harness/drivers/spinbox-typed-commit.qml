//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic

// Harness driver (run.sh --driver): text typed into StyledSpinBox is applied
// once on Enter or focus loss, clamped to the range, and never turns the value
// into NaN. Before the fix every keystroke assigned parseFloat(text) without
// emitting valueModified, so settings bound to valueModified missed typed
// values and an empty field produced NaN.
import QtQuick
import Quickshell
import qs.modules.common.widgets

ShellRoot {
    id: root

    // Each step types `text` and finishes editing; `value` and `modified` are
    // the expected spin box value and valueModified count afterwards.
    readonly property var steps: [
        { name: "typed value", text: "42", value: 42, modified: 1 },
        { name: "above range is clamped", text: "500", value: 100, modified: 2 },
        { name: "below range is clamped", text: "-7", value: 1, modified: 3 },
        { name: "empty text keeps value", text: "", value: 1, modified: 3 },
        { name: "non-number keeps value", text: "abc", value: 1, modified: 3 },
        { name: "same value is not a modification", text: "1", value: 1, modified: 3 }
    ]
    property int modifiedCount: 0
    property var window: null
    property var spin: null

    function report(payload) {
        console.info(`[harness:report] ${JSON.stringify(payload)}`);
    }

    function findInput(item) {
        for (const child of item.children) {
            if (child.hasOwnProperty("cursorPosition") && child.hasOwnProperty("readOnly"))
                return child;
            const found = root.findInput(child);
            if (found)
                return found;
        }
        return null;
    }

    function run() {
        const input = root.findInput(root.spin.contentItem);
        if (!input) {
            root.report({ type: "fatal", message: "spin box text input not found" });
            quitTimer.start();
            return;
        }
        root.report({ type: "spin", step: "typing allowed", expected: false, actual: input.readOnly });
        for (const step of root.steps) {
            input.forceActiveFocus();
            input.text = step.text;
            input.editingFinished();
            root.report({
                type: "spin",
                step: step.name,
                expected: { value: step.value, modified: step.modified, text: String(step.value) },
                actual: { value: root.spin.value, modified: root.modifiedCount, text: input.text }
            });
        }
        root.report({ type: "done" });
        quitTimer.start();
    }

    Component.onCompleted: {
        root.window = windowComponent.createObject(root);
        root.spin = root.window.spin;
        startTimer.start();
    }

    Component {
        id: windowComponent
        FloatingWindow {
            property alias spin: spinBox
            implicitWidth: 240
            implicitHeight: 80
            visible: true
            StyledSpinBox {
                id: spinBox
                from: 1
                to: 100
                value: 10
                onValueModified: root.modifiedCount++
            }
        }
    }

    Timer {
        id: startTimer
        interval: 300
        onTriggered: root.run()
    }

    Timer {
        id: quitTimer
        interval: 200
        onTriggered: Qt.quit()
    }
}
