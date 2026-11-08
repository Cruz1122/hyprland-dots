import QtQuick
import QtTest
import "../../config/quickshell/ii/modules/settings/backends/HyprlandLogic.js" as HL

TestCase {
    name: "HyprlandLogic"

    readonly property var e_gaps: ({ path: "general.gaps_in", type: "int" })
    readonly property var e_opacity: ({ path: "decoration.active_opacity", type: "real" })
    readonly property var e_layout: ({ path: "input.kb_layout", type: "list" })
    readonly property var e_variant: ({ path: "input.kb_variant", type: "string" })
    readonly property var e_vrr: ({ path: "misc.vrr", type: "enum", options: [{ value: 0 }, { value: 1 }, { value: 2 }] })
    readonly property var e_accel: ({ path: "input.accel_profile", type: "enum", options: [{ value: "" }, { value: "flat" }] })
    readonly property var e_tap: ({ path: "input.touchpad.tap_to_click", type: "bool" })

    function test_lua_paths() {
        verify(HL.isLuaPath("input.touchpad.tap_to_click"));
        verify(!HL.isLuaPath("input.touchpad.tap-to-click"));
        verify(!HL.isLuaPath("general.end"));
        verify(!HL.isLuaPath("a..b"));
        verify(!HL.isLuaPath("a}),os.exit(1"));
        compare(HL.overrideKey("input.touchpad.tap_to_click"), "input:touchpad:tap_to_click");
    }

    function test_types_come_from_the_registry() {
        compare(HL.luaType(e_opacity), "float");
        compare(HL.luaType(e_gaps), "int");
        compare(HL.luaType(e_vrr), "int");
        compare(HL.luaType(e_accel), "string");
        compare(HL.luaType(e_layout), "string");
        compare(HL.toArg(e_opacity, 1), "1.0");
        compare(HL.toArg(e_opacity, 0.85), "0.85");
        compare(HL.toArg(e_gaps, 4.4), "4");
        compare(HL.toArg(e_tap, false), "false");
        compare(HL.toArg(e_layout, ["us", "latam"]), "us,latam");
    }

    function test_from_hyprland_values() {
        compare(HL.fromHypr(e_gaps, "4 4 4 4"), 4, "css gaps use the first side");
        compare(HL.fromHypr(e_gaps, 7), 7);
        compare(HL.fromHypr(e_opacity, 1), 1);
        compare(HL.fromHypr(e_variant, "[[EMPTY]]"), "");
        compare(HL.fromHypr(e_layout, "us, latam"), ["us", "latam"]);
        compare(HL.fromHypr(e_layout, "[[EMPTY]]"), []);
        compare(HL.fromHypr(e_vrr, 2), 2);
        compare(HL.fromHypr(e_accel, "[[EMPTY]]"), "");
        compare(HL.fromHypr(e_tap, true), true);
        compare(HL.fromHypr(e_tap, 0), false);
        compare(HL.fromHypr(e_gaps, undefined), undefined);
    }

    function test_eval_expressions_escape_lua() {
        compare(HL.configExpression(e_tap, true), "hl.config({ input = { touchpad = { tap_to_click = true } } })");
        compare(HL.configExpression(e_layout, ["us", "latam"]), "hl.config({ input = { kb_layout = \"us,latam\" } })");
        compare(HL.configExpression(e_variant, "a\"b\\c"), "hl.config({ input = { kb_variant = \"a\\\"b\\\\c\" } })");
        compare(HL.configExpression(e_variant, "a\nb"), "", "control characters are rejected");
        compare(HL.configExpression({ path: "input.kb-layout", type: "string" }, "us"), "");
        compare(HL.configExpression(e_opacity, 0.5), "hl.config({ decoration = { active_opacity = 0.5 } })");
    }

    function test_game_mode_detection() {
        verify(HL.isGameModeActive("hl.config({animations={enabled=0}})\n"));
        verify(!HL.isGameModeActive("-- header\nhl.config({decoration={screen_shader=\"x\"}})\n"));
        verify(!HL.isGameModeActive(""));
    }

    function test_devices_and_binds() {
        verify(HL.hasTouchpad(JSON.stringify({ mice: [{ name: "elan1203:00-04f3:307a-touchpad" }] })));
        verify(!HL.hasTouchpad(JSON.stringify({ mice: [{ name: "logitech-g305-1" }] })));
        const binds = HL.parseBinds(JSON.stringify([
            { modmask: 64, key: "Return", has_description: false, description: "", dispatcher: "exec", arg: "kitty", submap: "" },
            { modmask: 65, key: "Q", has_description: true, description: "Close window", dispatcher: "killactive", arg: "", submap: "" },
            { modmask: 0, key: "", keycode: 0, catch_all: false, dispatcher: "x", arg: "" }
        ]));
        compare(binds.length, 2);
        compare(binds[0].keys, "Super + Shift + Q");
        compare(binds[0].action, "Close window");
        compare(binds[1].action, "exec kitty");
        compare(HL.filterBinds(binds, "super kitty").length, 1);
        compare(HL.filterBinds(binds, "").length, 2);
    }

    function test_xkb_list() {
        const parsed = HL.parseXkbList("! model\n  pc105  Generic 105-key PC\n\n! layout\n  us              English (US)\n  latam           Spanish (Latin American)\n\n! variant\n  intl            us: English (US, intl., with dead keys)\n\n! option\n  grp             Switching to another layout\n  grp:alt_shift_toggle Alt+Shift\n");
        compare(parsed.layouts.length, 2);
        compare(parsed.layouts[0].value, "us");
        compare(parsed.variants[0].layout, "us");
        compare(parsed.options.length, 1);
        compare(parsed.options[0].value, "grp:alt_shift_toggle");
    }
}
