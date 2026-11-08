import QtQuick
import QtTest
import "../../config/quickshell/ii/modules/settings/backends/AnimationLogic.js" as AL

// AnimationLogic.js. test_parity_cases reads tests/fixtures/animation-cases.json
// and hyprbase-sample.json with XMLHttpRequest, which Qt only allows with
// QML_XHR_ALLOW_FILE_READ=1: tests/test_animationsgen.py (ParityQmlTest) runs
// this file with it and requires the test to pass, not skip.
TestCase {
    name: "AnimationLogic"

    // config/hypr/hyprland/general.lua, as hyprbase.py reports it.
    readonly property var base: ({
        curves: {
            emphasizedDecel: { type: "bezier", points: [0.05, 0.7, 0.1, 1] },
            emphasizedAccel: { type: "bezier", points: [0.3, 0, 0.8, 0.15] },
            standardDecel: { type: "bezier", points: [0, 0, 0, 1] },
            menu_decel: { type: "bezier", points: [0.1, 1, 0, 1] },
            menu_accel: { type: "bezier", points: [0.52, 0.03, 0.72, 0.08] },
            stall: { type: "bezier", points: [1, -0.1, 0.7, 0.85] },
            expressiveFastSpatial: { type: "bezier", points: [0.42, 1.67, 0.21, 0.9] },
            expressiveSlowSpatial: { type: "bezier", points: [0.39, 1.29, 0.35, 0.98] },
            expressiveDefaultSpatial: { type: "bezier", points: [0.38, 1.21, 0.22, 1] }
        },
        animations: {
            windowsIn: { enabled: true, speed: 3, bezier: "emphasizedDecel", style: "popin 80%" },
            fadeIn: { enabled: true, speed: 3, bezier: "emphasizedDecel" },
            windowsOut: { enabled: true, speed: 2, bezier: "emphasizedDecel", style: "popin 90%" },
            fadeOut: { enabled: true, speed: 2, bezier: "emphasizedDecel" },
            windowsMove: { enabled: true, speed: 3, bezier: "emphasizedDecel", style: "slide" },
            border: { enabled: true, speed: 10, bezier: "emphasizedDecel" },
            layersIn: { enabled: true, speed: 2.7, bezier: "emphasizedDecel", style: "popin 93%" },
            layersOut: { enabled: true, speed: 2.4, bezier: "menu_accel", style: "popin 94%" },
            fadeLayersIn: { enabled: true, speed: 0.5, bezier: "menu_decel" },
            fadeLayersOut: { enabled: true, speed: 2.7, bezier: "stall" },
            workspaces: { enabled: true, speed: 7, bezier: "menu_decel", style: "slide" },
            specialWorkspaceIn: { enabled: true, speed: 2.8, bezier: "emphasizedDecel", style: "slidevert" },
            specialWorkspaceOut: { enabled: true, speed: 1.2, bezier: "emphasizedAccel", style: "slidevert" },
            zoomFactor: { enabled: true, speed: 3, bezier: "standardDecel" }
        }
    })
    readonly property var catalog: AL.curveCatalog(base, {})

    function readJson(path) {
        const request = new XMLHttpRequest();
        request.open("GET", Qt.resolvedUrl(path), false);
        request.send();
        return request.responseText.length > 0 ? JSON.parse(request.responseText) : null;
    }

    function test_cards() {
        compare(AL.CARD_IDS.length, 10);
        compare(AL.card("windowsIn").companion, "fadeIn");
        compare(AL.card("layersOut").companion, "fadeLayersOut");
        compare(AL.card("border").family, "none");
        compare(AL.cardOf({ key: "animation.windowsIn", path: "windowsIn" }), "windowsIn");
        compare(AL.cardOf({ key: "animation.zoomFactor", path: "animation.zoomFactor" }), "zoomFactor");
        verify(AL.card("fadeIn") === null);
    }

    function test_value_resolution() {
        const managed = { windowsIn: { enabled: false, speed: 2, curve: "linear", style: "" } };
        compare(AL.cardValue("windowsIn", managed, base), managed.windowsIn, "managed first");
        compare(AL.cardValue("windowsOut", managed, base), { enabled: true, speed: 2, curve: "emphasizedDecel", style: "popin 90%" }, "then the base");
        compare(AL.cardValue("windowsOut", {}, null), { enabled: true, speed: 8, curve: "default", style: "" }, "then the compiled default (global)");
        compare(AL.baseCard("border", null), undefined, "no base, no default");
        // A base without the leaf inherits from its nearest ancestor.
        const partial = { animations: { windows: { enabled: true, speed: 5, bezier: "linear", style: "slide" } } };
        compare(AL.cardValue("windowsMove", {}, partial), { enabled: true, speed: 5, curve: "linear", style: "slide" });
        compare(AL.resolveLeaf({ animations: { fadeDpms: { enabled: false } } }, "fadeDpms"),
                { enabled: false, speed: 1, curve: "default", style: "" });
        compare(AL.resolveLeaf(null, "borderangle").enabled, false);
    }

    function test_styles() {
        compare(AL.parseStyle("windowsIn", "popin 80%"), { kind: "popin", percent: 80, direction: "", known: true, raw: "popin 80%" });
        compare(AL.parseStyle("layersIn", "slide left").direction, "left");
        compare(AL.parseStyle("workspaces", "slidefade 20%").percent, 20);
        const odd = AL.parseStyle("windowsIn", "slidefade 20%");
        compare(odd.known, false);
        compare(odd.raw, "slidefade 20%");
        compare(AL.formatStyle("windowsIn", odd), "slidefade 20%", "unknown styles are kept as they are");
        compare(AL.formatStyle("windowsIn", { kind: "popin", percent: 85 }), "popin 85%");
        compare(AL.formatStyle("windowsIn", { kind: "popin", percent: 140 }), "popin 100%");
        compare(AL.formatStyle("windowsIn", { kind: "slide", direction: "top" }), "slide top");
        compare(AL.formatStyle("workspaces", { kind: "slide", direction: "top" }), "slide", "workspaces take no side");
        compare(AL.formatStyle("border", { kind: "none" }), "");
        for (const id of AL.CARD_IDS) {
            for (const option of AL.styleOptions(id)) {
                const text = AL.formatStyle(id, { kind: option.kind, percent: option.percent ? 50 : null, direction: option.directions[0] ?? "" });
                verify(AL.parseStyle(id, text).known, `${id}: ${text}`);
                verify(option.label.length > 0 && option.description.length > 0);
            }
        }
        compare(AL.styleOptions("border"), []);
        compare(AL.styleOptions("windowsIn").map(o => o.kind), ["slide", "popin", "gnomed"]);
        // Workspaces move as a whole and offer no side: their slide text is not the windows' one.
        const slideOf = id => AL.styleOptions(id).find(o => o.kind === "slide").description;
        compare(slideOf("workspaces"), "The whole workspace moves sideways, as far as the screen is wide; the auxiliary workspace (Super+S) also fades.");
        compare(slideOf("specialWorkspaceIn"), slideOf("workspaces"));
        // Hyprland 0.57 always fades a special workspace too, whatever its style.
        for (const kind of ["slide", "slidevert"])
            verify(AL.styleOptions("specialWorkspaceIn").find(o => o.kind === kind).description.includes("also fades"), kind);
        // windowsMove shares the windows styles, which Hyprland only uses to open and close.
        for (const option of AL.styleOptions("windowsMove"))
            verify(option.description.includes("moves ignore it"), option.kind);
        verify(slideOf("windowsIn").includes("pick a side"));
        verify(!slideOf("workspaces").includes("pick a side"), "no side to pick on workspaces");
        // Panels have no move animation, so their slide text keeps no move remark.
        verify(slideOf("layersIn").includes("pick a side") && !slideOf("layersIn").includes("moves ignore it"));
    }

    function test_catalog() {
        const user = { ii_mine: { type: "bezier", points: [0.2, 0, 0, 1], label: "Mine" }, bad_name: { type: "bezier", points: [0, 0, 1, 1] } };
        const list = AL.curveCatalog(base, user);
        const names = list.map(c => c.name);
        compare(names.slice(0, 2), ["default", "linear"]);
        verify(names.includes("emphasizedDecel"));
        verify(!names.includes("bad_name"));
        const mine = AL.findCurve(list, "ii_mine");
        compare([mine.group, mine.builtin, mine.label], ["user", false, "Mine"]);
        const decel = AL.findCurve(list, "emphasizedDecel");
        compare([decel.group, decel.builtin, decel.label], ["dotfiles", true, "Quick start, gentle stop"]);
        compare(AL.findCurve(list, "default").label, "Hyprland standard");
        compare(AL.findCurve(list, "ii_spring_soft").group, "app");
        verify(AL.isSpring(list, "ii_spring_bouncy"));
        compare(AL.curveCatalog(null, {}).map(c => c.group), ["hyprland", "hyprland", "app", "app"]);
        // Unknown dotfiles curves keep their identifier as the label.
        compare(AL.findCurve(AL.curveCatalog({ curves: { myCurve: { type: "bezier", points: [0, 0, 1, 1] } } }, {}), "myCurve").label, "myCurve");
    }

    function test_companions() {
        compare(AL.companionValue("layersIn", { enabled: true, speed: 1.8, curve: "emphasizedDecel", style: "" }, base, catalog),
                { enabled: true, speed: 0.33, curve: "menu_decel", style: "" });
        compare(AL.companionValue("layersOut", { enabled: true, speed: 100, curve: "emphasizedDecel", style: "" }, base, catalog).speed, 100);
        compare(AL.companionValue("windowsIn", { enabled: true, speed: 4, curve: "ii_spring_soft", style: "" }, base, catalog).speed, 3,
                "springs keep the base speed");
        compare(AL.companionValue("border", { enabled: true, speed: 4, curve: "linear", style: "" }, base, catalog), null);
        compare(AL.round2(0.125), 0.13, "halves round up on both sides");
    }

    function test_presets() {
        compare(AL.presetFor({}, base), "default");
        compare(AL.presetFor({}, null), "default");
        for (const id of ["agile", "smooth", "bouncy", "minimal"]) {
            const cards = AL.presetCards(id, base);
            compare(Object.keys(cards).length, 10);
            compare(AL.presetFor(cards, base), id);
            for (const cardId in cards)
                verify(AL.validateCard(cardId, cards[cardId], catalog).ok, `${id}/${cardId}`);
        }
        const agile = AL.presetCards("agile", base);
        compare(agile.windowsOut, { enabled: true, speed: 1.4, curve: "emphasizedDecel", style: "popin 90%" }, "unlisted fields keep the base");
        compare(agile.workspaces, { enabled: true, speed: 4.5, curve: "menu_decel", style: "slide" });
        compare(AL.presetCards("bouncy", base).specialWorkspaceOut, AL.baseCard("specialWorkspaceOut", base));
        const tweaked = Object.assign({}, agile, { border: { enabled: true, speed: 7, curve: "emphasizedDecel", style: "" } });
        compare(AL.presetFor(tweaked, base), "custom");
        compare(AL.presetFor({ border: AL.baseCard("border", base) }, base), "default", "managed values equal to the base");
        compare(AL.presetFor(agile, null), "custom", "no base: only default is known");
        compare(AL.presetCards("default", base), null);
        compare(AL.presetCards("agile", null), null);
        compare(AL.presets().map(p => p.value), ["default", "agile", "smooth", "bouncy", "minimal"]);
    }

    function test_curve_usage() {
        const managed = { border: { enabled: true, speed: 3, curve: "ii_mine", style: "" } };
        compare(AL.curveUsage("ii_mine", managed, base), ["border"]);
        compare(AL.curveUsage("emphasizedDecel", managed, base), ["windowsIn", "windowsOut", "windowsMove", "specialWorkspaceIn", "layersIn"]);
    }

    function test_summary_parts() {
        const parts = AL.summaryParts("windowsIn", { enabled: true, speed: 3, curve: "emphasizedDecel", style: "popin 80%" }, catalog);
        compare(parts.style.label, "Pop in");
        compare(parts.style.percent, 80);
        compare(parts.durationMs, 300);
        compare(parts.curve.label, "Quick start, gentle stop");
        compare(AL.summaryParts("windowsIn", { enabled: true, speed: 1.5, curve: "standardDecel", style: "popin 100%" }, catalog).style.label, "Fade only");
        const spring = AL.summaryParts("windowsIn", { enabled: true, speed: 3, curve: "ii_spring_soft", style: "" }, catalog);
        compare([spring.spring, spring.durationMs], [true, null]);
        compare(AL.summaryParts("border", { enabled: false, speed: 10, curve: "emphasizedDecel", style: "" }, catalog).style, null);
        const odd = AL.summaryParts("windowsIn", { enabled: true, speed: 3, curve: "gone", style: "weird" }, catalog);
        compare([odd.style.known, odd.style.raw, odd.style.label, odd.curve.known], [false, "weird", "Not recognized: %1", false]);
    }

    function test_loaded_confirmation() {
        const managed = {
            windowsIn: { enabled: true, speed: 0.33333, curve: "ii_spring_soft", style: "popin 85%" },
            border: { enabled: false, speed: 4, curve: "linear", style: "" }
        };
        const good = JSON.stringify([[
            { name: "windowsIn", overridden: true, bezier: "spring:ii_spring_soft", enabled: true, speed: 0.33, style: "popin 85%" },
            { name: "border", overridden: true, bezier: "default", enabled: false, speed: 1, style: "" }
        ], []]);
        compare(AL.loadedMismatches(good, managed, catalog), []);
        const stale = JSON.stringify([[
            { name: "windowsIn", overridden: true, bezier: "emphasizedDecel", enabled: true, speed: 3, style: "popin 80%" },
            { name: "border", overridden: false, bezier: "", enabled: true, speed: 0, style: "" }
        ], []]);
        compare(AL.loadedMismatches(stale, managed, catalog), ["windowsIn", "border"]);
        compare(AL.loadedMismatches("not json", managed, catalog), ["windowsIn", "border"]);
        // A different curve or style alone is a mismatch too.
        const otherCurve = JSON.stringify([[
            { name: "windowsIn", overridden: true, bezier: "ii_spring_soft", enabled: true, speed: 0.33, style: "popin 85%" }
        ], []]);
        compare(AL.loadedMismatches(otherCurve, { windowsIn: managed.windowsIn }, catalog), ["windowsIn"], "spring without the prefix");
        const otherBezier = JSON.stringify([[
            { name: "windowsOut", overridden: true, bezier: "menu_decel", enabled: true, speed: 2, style: "popin 90%" }
        ], []]);
        const windowsOut = { windowsOut: { enabled: true, speed: 2, curve: "emphasizedDecel", style: "popin 90%" } };
        compare(AL.loadedMismatches(otherBezier, windowsOut, catalog), ["windowsOut"], "different bezier");
        const otherStyle = JSON.stringify([[
            { name: "windowsOut", overridden: true, bezier: "emphasizedDecel", enabled: true, speed: 2, style: "popin 80%" }
        ], []]);
        compare(AL.loadedMismatches(otherStyle, windowsOut, catalog), ["windowsOut"], "different style");
        const same = JSON.stringify([[
            { name: "windowsOut", overridden: true, bezier: "emphasizedDecel", enabled: true, speed: 2, style: "popin 90%" }
        ], []]);
        compare(AL.loadedMismatches(same, windowsOut, catalog), [], "control: the same tuple");
        // A failed read is not a parsed answer (the backend retries later).
        compare(AL.animationList("not json"), null);
        compare(AL.animationList(""), null);
        compare(AL.animationList('{"a": 1}'), null);
        compare(AL.animationList(same).length, 1);
    }

    function test_requires_animations() {
        verify(AL.requiresAnimations('    pcall(require, "custom.shell-animations")'));
        verify(AL.requiresAnimations('require("custom.shell-animations")'));
        verify(!AL.requiresAnimations('require("custom.shell-settings")'));
        verify(!AL.requiresAnimations('-- pcall(require, "custom.shell-animations")\n'), "line comment");
        verify(!AL.requiresAnimations('x = 1 -- require("custom.shell-animations")\n'), "trailing comment");
        verify(!AL.requiresAnimations('--[[\npcall(require, "custom.shell-animations")\n]]\n'), "block comment");
        verify(!AL.requiresAnimations('--[==[ ]] pcall(require, "custom.shell-animations") ]==]\n'), "leveled block comment");
        verify(AL.requiresAnimations('--[[ old ]] pcall(require, "custom.shell-animations")\n'), "code after a block comment");
        verify(AL.requiresAnimations('local s = "--[[" pcall(require, "custom.shell-animations")\n'), "a string is not a comment");
        verify(AL.requiresAnimations("local s = [[ -- ]] pcall(require, 'custom.shell-animations')\n"), "a long string is not a comment");
        compare(AL.stripLuaComments('a -- b\nc --[[ d\ne ]] f'), "a \nc   f");
    }

    function readText(path) {
        const request = new XMLHttpRequest();
        request.open("GET", Qt.resolvedUrl(path), false);
        request.send();
        return request.responseText;
    }

    // The real loader block of config/hypr/hyprland.lua, so a change to it
    // that the capability check would miss fails here.
    function test_real_loader_block() {
        const real = readText("../../config/hypr/hyprland.lua");
        if (!real)
            skip("needs QML_XHR_ALLOW_FILE_READ=1 (tests/test_settings_qml.py runs it)");
        verify(real.indexOf("custom.shell-animations") >= 0, "hyprland.lua names the generated file");
        verify(AL.requiresAnimations(real), "hyprland.lua loads custom/shell-animations.lua");
        // Control: the same file with the loader commented out is not detected.
        const commented = real.split("\n").map(line => line.indexOf("custom.shell-animations") >= 0 ? "-- " + line : line).join("\n");
        verify(!AL.requiresAnimations(commented), "the loader commented out");
    }

    function test_labels() {
        compare(AL.labelProblem("Mine"), "");
        compare(AL.labelProblem("   "), "The name cannot be empty");
        compare(AL.labelProblem("a\nb"), "The name contains control characters");
        compare(AL.labelProblem("x".repeat(41)), "The name is longer than 40 characters");
        compare(AL.labelProblem("\u{1F600}".repeat(40)), "", "length counts code points");
        verify(!AL.isUserCurveName("ii_spring_soft"), "app springs are not user curves");
    }

    function test_parity_cases() {
        const cases = readJson("../fixtures/animation-cases.json");
        const sample = readJson("../fixtures/hyprbase-sample.json");
        if (!cases || !sample)
            skip("needs QML_XHR_ALLOW_FILE_READ=1 (tests/test_animationsgen.py runs it)");
        const list = AL.curveCatalog(sample, cases.userCurves);
        for (const c of cases.cards)
            compare(AL.validateCard(c.card, c.value, list).ok, c.valid, `card ${JSON.stringify(c)}`);
        for (const c of cases.curves)
            compare(AL.validateCurve(c.name, c.desc).ok, c.valid, `curve ${JSON.stringify(c)}`);
        for (const c of cases.styles) {
            const parsed = AL.parseStyle(c.card, c.style);
            compare(parsed.known, c.known, `style ${JSON.stringify(c)}`);
            if (c.known)
                compare([parsed.kind, parsed.percent, parsed.direction], [c.kind, c.percent, c.direction], `style ${JSON.stringify(c)}`);
        }
        for (const c of cases.companions)
            compare(AL.companionValue(c.card, c.primary, sample, list), c.expect, `companion ${JSON.stringify(c)}`);
        verify(cases.bases.length > 0, "base cases");
        for (const c of cases.bases) {
            for (const leaf in c.expect)
                compare(AL.resolveLeaf(c.base, leaf), c.expect[leaf], `base ${c.name}: ${leaf}`);
            compare(AL.curveCatalog(c.base, {}).filter(k => k.group === "dotfiles").map(k => k.name).sort(), c.curves, `base ${c.name}: curves`);
        }
    }
}
