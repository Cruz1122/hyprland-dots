import QtQuick
import QtTest
import "../../config/quickshell/ii/modules/settings/components/WindowPreviewLogic.js" as PL
import "../../config/quickshell/ii/modules/settings/pages/WindowsLogic.js" as WL

// Geometry of SettingsWindowPreview (WindowPreviewLogic.js); the harness
// driver tests/harness/drivers/window-preview.qml checks the drawn component.
TestCase {
    name: "SettingsWindowPreview"

    readonly property var values: ({
        gapsIn: 4, gapsOut: 5, border: 1, rounding: 18, roundingPower: 2.5,
        blur: true, blurSize: 10, blurPasses: 3, shadow: true, shadowRange: 20, shadowPower: 4,
        dim: true, dimStrength: 0.05, activeOpacity: 1, inactiveOpacity: 0.9
    })

    function test_normalize_marks_missing_values_as_examples() {
        const full = PL.normalize(values);
        compare(full.known, true);
        compare(full.inactiveOpacity, 0.9);
        const partial = PL.normalize({ gapsIn: 12 });
        compare(partial.known, false);
        compare(partial.gapsIn, 12);
        compare(partial.gapsOut, PL.EXAMPLE.gapsOut);
        compare(PL.normalize(undefined).known, false);
        compare(PL.normalize({ gapsIn: -3, roundingPower: 50, dimStrength: "x", blur: "yes" }).gapsIn, 0);
        compare(PL.normalize({ roundingPower: 50 }).roundingPower, 10);
        compare(PL.normalize({ dimStrength: "x" }).dimStrength, PL.EXAMPLE.dimStrength);
        compare(PL.normalize({ blur: "yes" }).blur, PL.EXAMPLE.blur, "only booleans count");
        compare(PL.normalize({ gapsIn: true }).gapsIn, PL.EXAMPLE.gapsIn, "a boolean is not a number");
    }

    function test_tiles_follow_gaps_out_gaps_in_and_border() {
        const v = PL.normalize(values);
        const tiles = PL.tiledWindows(v);
        compare(tiles.length, 3);
        const main = tiles[0], top = tiles[1], bottom = tiles[2];
        // Screen edge: gaps_out from the work area (below the bar).
        compare(main.box.x, 5);
        compare(main.box.y, PL.BAR_HEIGHT + 5);
        compare(top.box.x + top.box.width, PL.SCREEN_WIDTH - 5);
        compare(main.box.y + main.box.height, PL.SCREEN_HEIGHT - 5);
        // Neighbors are 2 × gaps_in apart, horizontally and vertically.
        compare(top.box.x - (main.box.x + main.box.width), 8);
        compare(bottom.box.y - (top.box.y + top.box.height), 8);
        // The live session puts a window's content at gaps_out + border (x = 6).
        compare(main.content.x, 6);
        compare(main.content.width, main.box.width - 2);
        compare(main.radius, 18);
        compare(main.outerRadius, 19);
        verify(main.active && !top.active && !bottom.active);
    }

    function test_changing_values_moves_the_geometry() {
        const wide = PL.tiledWindows(PL.normalize(Object.assign({}, values, { gapsIn: 20, gapsOut: 30, border: 4, rounding: 0 })));
        compare(wide[1].box.x - (wide[0].box.x + wide[0].box.width), 40);
        compare(wide[0].box.x, 30);
        compare(wide[0].content.x, 34);
        compare(wide[0].radius, 0);
        compare(wide[0].outerRadius, 0, "square corners stay square outside the border too");
        const huge = PL.tiledWindows(PL.normalize(Object.assign({}, values, { rounding: 200 })));
        compare(huge[1].radius, huge[1].content.height / 2, "rounding is clamped to half the shorter side");
    }

    function test_desktop_scales_and_keeps_thin_borders_visible() {
        const d = PL.desktop(values, 320);
        compare(d.scale, 0.25);
        compare(d.width, 320);
        compare(d.height, 200);
        compare(d.bar.height, 10);
        compare(d.tiled[0].box.x, 1.25);
        compare(d.tiled[0].border, 1, "a 1 px border would be 0.25 px: drawn 1 px");
        compare(d.tiled[0].content.x, d.tiled[0].box.x + 1);
        compare(PL.desktop(Object.assign({}, values, { border: 0 }), 320).tiled[0].border, 0);
        compare(PL.desktop(Object.assign({}, values, { border: 8 }), 320).tiled[0].border, 2);
        compare(d.floating.shadowRange, 5);
        compare(PL.desktop(Object.assign({}, values, { shadow: false }), 320).floating.shadowRange, 0);
        compare(PL.desktop(Object.assign({}, values, { shadow: false }), 320).shadowBlur, 0);
    }

    function test_effects() {
        const v = PL.normalize(values);
        compare(PL.blurRadius(v), 45);
        compare(PL.blurRadius(PL.normalize(Object.assign({}, values, { blur: false }))), 0);
        verify(PL.shadowBlur(PL.normalize(Object.assign({}, values, { shadowPower: 1 }))) > PL.shadowBlur(v),
            "higher render power gives a shorter shadow");
        compare(PL.shownDim(v), 0.15, "dimming is exaggerated three times");
        compare(PL.shownDim(PL.normalize(Object.assign({}, values, { dimStrength: 0.9 }))), 0.75);
        compare(PL.shownDim(PL.normalize(Object.assign({}, values, { dim: false }))), 0);
    }

    function test_superellipse_corners() {
        const box = { x: 0, y: 0, width: 100, height: 60 };
        const square = PL.roundedRectPoints(box, 0, 2, 8);
        compare(square.length, 4);
        const circle = PL.roundedRectPoints(box, 20, 2, 8);
        compare(circle.length, 36);
        // Starts at the top tangent of the top-right corner and goes
        // clockwise; the top-left corner ends at its top tangent.
        compare(circle[0].x, 80);
        compare(circle[0].y, 0);
        fuzzyCompare(circle[8].x, 100, 1e-9);
        fuzzyCompare(circle[8].y, 20, 1e-9);
        fuzzyCompare(circle[27].x, 0, 1e-9);
        fuzzyCompare(circle[27].y, 20, 1e-9);
        fuzzyCompare(circle[35].x, 20, 1e-9);
        fuzzyCompare(circle[35].y, 0, 1e-9);
        // Every point of a power-2 corner lies on the circle.
        for (let i = 0; i <= 8; i++)
            fuzzyCompare(Math.hypot(circle[i].x - 80, circle[i].y - 20), 20, 1e-9);
        // The diagonal point moves towards the corner as the power grows.
        const mid = p => PL.roundedRectPoints(box, 20, p, 8)[4];
        verify(mid(4).x > mid(2).x && mid(4).y < mid(2).y);
        fuzzyCompare(PL.cornerInset(2), 1 - Math.SQRT1_2, 1e-12);
        verify(PL.cornerInset(10) < PL.cornerInset(2.5));
    }

    function test_magnifier_places_the_corner_at_the_anchor() {
        const l = PL.magnifier(values, 184, 150, 78, 76);
        compare(l.main.box.x + l.main.box.width, 78);
        compare(l.main.box.y, 76);
        compare(l.neighbor.box.x, 78 + 8, "the neighbor is 2 × gaps_in to the right");
        compare(l.bar.y + l.bar.height, 76 - 5, "the work area starts gaps_out above the corner");
        compare(l.border.size, 1);
        compare(l.rounding.size, 18);
        compare(l.rounding.power, 2.5);
        const big = PL.magnifier(Object.assign({}, values, { gapsIn: 40, gapsOut: 60 }), 184, 150, 78, 76);
        compare(big.neighbor.box.x, 158);
        compare(big.bar.y + big.bar.height, 16);
    }

    function test_parts_and_rows() {
        compare(PL.partForKey("hyprland.general.gaps_in"), "gapsIn");
        compare(PL.partForKey("hyprland.decoration.rounding_power"), "roundingPower");
        compare(PL.partForKey("hyprland.decoration.shadow.range"), "shadow");
        compare(PL.partForKey("hyprland.misc.vrr"), "");
        compare(PL.partForKey(""), "");
        for (const name in PL.VALUE_KEYS)
            verify(PL.VALUE_KEYS[name].indexOf("hyprland.") === 0, name);
        const row = { objectName: "row:hyprland.general.gaps_in", parent: null };
        const inner = { objectName: "", parent: { objectName: "control", parent: row } };
        compare(WL.rowKeyOf(inner), "hyprland.general.gaps_in");
        compare(WL.rowKeyOf(null), "");
        compare(WL.rowKeyOf({ objectName: "x", parent: null }), "");
    }

    function test_hovered_key_follows_enter_and_leave() {
        const a = "hyprland.general.gaps_in", b = "hyprland.general.border_size";
        compare(WL.nextHoveredKey("", a, true), a);
        compare(WL.nextHoveredKey(a, a, false), "");
        // Entering B before A reports its leave: leaving A keeps B.
        compare(WL.nextHoveredKey(a, b, true), b);
        compare(WL.nextHoveredKey(b, a, false), b);
        compare(WL.nextHoveredKey("", a, false), "");
    }

    function test_border_colour_from_getoption() {
        compare(PL.borderColor('{"option": "general:col.active_border", "gradient": "77474747 0deg", "set": true }'), "#77474747");
        compare(PL.borderColor('{"option": "general:col.active_border", "gradient": "ff0db7d4 ff00ff00 45deg", "set": true }'), "#ff0db7d4");
        compare(PL.borderColor('{"option": "general:col.active_border", "str": "ffffffff 0deg", "set": false}'), "#ffffffff");
        compare(PL.borderColor("no such option"), "");
        compare(PL.borderColor('{"option": "x", "int": 3}'), "");
        compare(PL.borderColor("[]"), "");
    }
}
