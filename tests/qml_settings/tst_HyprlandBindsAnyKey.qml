import QtQuick
import QtTest
import "../../config/quickshell/ii/modules/settings/backends/HyprlandLogic.js" as HL

// Catch-all binds in Input > "Active shortcuts": InputPage passes the
// translated "Any key" label, so the row and the filter use the user's words.
TestCase {
    name: "HyprlandBindsAnyKey"

    readonly property string binds: JSON.stringify([
        { modmask: 64, key: "", keycode: 0, catch_all: true, has_description: false, description: "", dispatcher: "submap", arg: "reset", submap: "vm" },
        { modmask: 64, key: "Return", has_description: false, description: "", dispatcher: "exec", arg: "kitty", submap: "" }
    ])

    function test_catch_all_uses_the_given_label() {
        const parsed = HL.parseBinds(binds, "Cualquier tecla");
        compare(parsed.length, 2);
        const catchAll = parsed.find(b => b.action === "submap reset");
        compare(catchAll.keys, "vm: Super + Cualquier tecla");
        compare(HL.filterBinds(parsed, "cualquier tecla").length, 1);
        compare(HL.filterBinds(parsed, "any key").length, 0);
    }

    function test_catch_all_defaults_to_english() {
        const catchAll = HL.parseBinds(binds).find(b => b.action === "submap reset");
        compare(catchAll.keys, "vm: Super + Any key");
    }
}
