import QtQuick
import QtTest
import "../../config/quickshell/ii/modules/common/functions/DisplayRules.js" as DisplayRules

TestCase {
    name: "DisplayRules"

    readonly property var laptop: ({
        name: "eDP-1",
        availableModes: ["1920x1080@144.00Hz", "1920x1080@60.00Hz", "1280x720@60.00Hz"]
    })

    function test_quoteLua() {
        compare(DisplayRules.quoteLua("eDP-1"), '"eDP-1"');
        compare(DisplayRules.quoteLua('a"b\\c'), '"a\\"b\\\\c"');
        compare(DisplayRules.quoteLua(1), '"1"');
    }

    function test_modeFor() {
        compare(DisplayRules.modeFor(laptop, 1920, 1080, 144.003), "1920x1080@144.00Hz");
        compare(DisplayRules.modeFor(laptop, 1920, 1080, 75), "1920x1080@144.00Hz");
        compare(DisplayRules.modeFor(laptop, 1280, 720, 60), "1280x720@60.00Hz");
        compare(DisplayRules.modeFor(laptop, 800, 600, 60), "preferred");
        compare(DisplayRules.modeFor({ name: "X" }, 800, 600, 60), "preferred");
    }

    function test_monitorRule() {
        compare(DisplayRules.monitorRule(laptop, false, null),
            '{ output = "eDP-1", mode = "preferred", position = "auto", scale = "1", disabled = false }');
        compare(DisplayRules.monitorRule(laptop, true, null),
            '{ output = "eDP-1", mode = "preferred", position = "auto", scale = "1", disabled = true }');
        compare(DisplayRules.monitorRule({ name: "HDMI-A-1" }, false, "eDP-1", "1920x1080@60.00Hz", "1"),
            '{ output = "HDMI-A-1", mode = "1920x1080@60.00Hz", position = "auto", scale = "1", disabled = false, mirror = "eDP-1" }');
    }
}
