import QtQuick
import QtTest
import "../../config/quickshell/ii/modules/ii/bar"

TestCase {
    id: testCase
    name: "AiEmblemState"
    width: 260
    height: 180
    visible: true
    when: windowShown

    MouseArea {
        id: icon
        x: 20; y: 20; width: 30; height: 30
        hoverEnabled: true
    }
    MouseArea {
        id: popup
        x: 20; y: 70; width: 180; height: 60
        visible: state.showing
        hoverEnabled: true
    }
    AiEmblemState {
        id: state
        rotationInterval: 400
        closeDelay: 70
        pointerHovered: icon.containsMouse
        popupHovered: popup.containsMouse
    }
    SignalSpy { id: indexChanged; target: state; signalName: "currentIndexChanged" }

    function init() {
        mouseMove(testCase, 240, 160);
        state.active = false;
        wait(100);
        state.currentIndex = 0;
        state.active = true;
        indexChanged.clear();
    }

    function test_real_pointer_holds_popup_and_rotation() {
        mouseMove(icon, 10, 10);
        tryCompare(state, "showing", true);
        verify(state.held);
        wait(600);
        compare(state.currentIndex, 0);
        compare(state.imageOpacity, 1);
        mouseMove(popup, 30, 20);
        wait(120);
        verify(state.showing);
        verify(state.held);
        compare(state.currentIndex, 0);
        mouseMove(testCase, 240, 160);
        tryCompare(state, "showing", false);
        tryCompare(state, "held", false);
        tryVerify(() => indexChanged.count > 0, 1200);
    }

    function test_hover_mid_fade_pins_a_readable_icon() {
        tryVerify(() => state.imageOpacity < .9, 1000);
        mouseMove(icon, 10, 10);
        tryCompare(state, "held", true);
        const pinned = state.currentIndex;
        compare(state.imageOpacity, 1);
        wait(600);
        compare(state.currentIndex, pinned);
        compare(state.imageOpacity, 1);
    }

    function test_hidden_emblem_closes_popup() {
        mouseMove(icon, 10, 10);
        tryCompare(state, "showing", true);
        state.active = false;
        compare(state.showing, false);
        compare(state.imageOpacity, 1);
    }
}
