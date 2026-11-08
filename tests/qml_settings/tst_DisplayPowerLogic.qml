import QtQuick
import QtTest
import "../../config/quickshell/ii/modules/settings/backends/DisplayLogic.js" as DisplayLogic
import "../../config/quickshell/ii/modules/settings/backends/PowerLogic.js" as PowerLogic

// Runs DisplayLogic in the Qt engine (its `.import` of DisplayRules included);
// tests/test_settings_display_power.py checks the generator round trip.
TestCase {
    name: "DisplayPowerLogic"

    readonly property var infos: [
        { id: 0, name: "eDP-1", width: 1920, height: 1080, refreshRate: 144.003, x: 0, y: 0, scale: 1, transform: 0,
          vrr: false, disabled: false, mirrorOf: "none", currentFormat: "XRGB8888",
          availableModes: ["1920x1080@144.00Hz", "1920x1080@60.00Hz"] },
        { id: 1, name: "HDMI-A-1", width: 1920, height: 1080, refreshRate: 60, x: 0, y: 0, scale: 1, transform: 0,
          vrr: false, disabled: false, mirrorOf: "0", currentFormat: "XRGB8888",
          availableModes: ["1920x1080@60.00Hz", "1280x720@60.00Hz"] }
    ]

    function test_specFromMonitors() {
        const spec = DisplayLogic.specFromMonitors(infos);
        compare(spec.length, 2);
        compare(spec[0].mode, "1920x1080@144.00Hz");
        compare(spec[1].mirror, "eDP-1");
        compare(spec[1].bitdepth, null);
        compare(DisplayLogic.arrangement(spec, infos, "HDMI-A-1"), "mirror:eDP-1");
    }

    function test_setField_keeps_an_output() {
        const spec = DisplayLogic.specFromMonitors(infos);
        const off = DisplayLogic.setField(spec, "eDP-1", "enabled", false);
        compare(off[0].enabled, false);
        compare(off[1].mirror, null, "a mirror of a disabled output is cleared");
        compare(DisplayLogic.setField(off, "HDMI-A-1", "enabled", false), null);
        compare(spec[0].enabled, true, "inputs are not mutated");
        compare(DisplayLogic.validate([]), "No displays found");
    }

    function test_rotated_logical_size() {
        const size = DisplayLogic.logicalSize({ mode: "1920x1080@60", scale: 1.5, transform: 1 }, null);
        compare(size.width, 720);
        compare(size.height, 1280);
    }

    function test_modeChoices() {
        const choices = DisplayLogic.modeChoices(infos[1], "1920x1080@60.00Hz");
        compare(choices.map(c => c.value), ["preferred", "1920x1080@60.00Hz", "1280x720@60.00Hz"]);
        compare(choices[1].label, "1920 × 1080 · 60 Hz");
    }

    function test_generatorArgs() {
        const args = DisplayLogic.generatorArgs("/s/monitorsgen.py", "/h/monitors.lua", [{ name: "eDP-1" }], "expr", false);
        compare(args.slice(0, 3), ["python3", "/s/monitorsgen.py", "--lua-expr"]);
        compare(JSON.parse(args[args.length - 1]), { monitors: [{ name: "eDP-1" }] });
        verify(DisplayLogic.generatorArgs("/s/m.py", "/h/m.lua", [], "write", true).includes("--force"));
        verify(DisplayLogic.isManagedText(DisplayLogic.MONITORS_MARKER + "\nhl.monitor({})\n"));
        verify(!DisplayLogic.isManagedText("hl.monitor({})\n"));
    }

    function test_power_profiles() {
        compare(PowerLogic.profileName(0, 0, 2), "power-saver");
        compare(PowerLogic.profileName(1, 0, 2), "balanced");
        compare(PowerLogic.profileName(2, 0, 2), "performance");
        const options = [{ value: "power-saver", label: "A" }, { value: "balanced", label: "B" }, { value: "performance", label: "C" }];
        compare(PowerLogic.profileChoices(options, false).map(o => o.value), ["power-saver", "balanced"]);
        compare(PowerLogic.profileChoices(options, true).length, 3);
    }
}
