import QtQuick
import QtTest
import "../../config/quickshell/ii/modules/settings/components/AnimationsPageLogic.js" as PageLogic

// AnimationsPageLogic.js: the pure helpers of the Animations page widgets
// (cards, preset row, curve library). `tr` is the identity here, so the
// expected texts are the English source strings.
TestCase {
    name: "SettingsAnimationPageLogic"

    function tr(text) {
        return text;
    }

    readonly property var catalog: [
        { name: "emphasizedDecel", type: "bezier", points: [0.05, 0.7, 0.1, 1], label: "Quick start, gentle stop", group: "dotfiles", builtin: true },
        { name: "ii_spring_soft", type: "spring", mass: 1, stiffness: 238.1191, damping: 24.21279333, label: "Soft spring", group: "app", builtin: true },
        { name: "ii_curve_1", type: "bezier", points: [0.2, 0, 0, 1], label: "Mi curva", group: "user", builtin: false }
    ]

    function test_roundedSettleMs() {
        compare(PageLogic.roundedSettleMs(647), 650);
        compare(PageLogic.roundedSettleMs(924), 920);
        compare(PageLogic.roundedSettleMs(0), 0);
    }

    function test_sliderMs_clamps_to_the_ui_range() {
        compare(PageLogic.sliderMs(3), 300);
        compare(PageLogic.sliderMs(0.2), 50);
        compare(PageLogic.sliderMs(70), 2000);
        compare(PageLogic.sliderMs(2.55), 255);
        compare(PageLogic.sliderMs("x"), 50);
    }

    function test_curveLabel_keeps_user_text() {
        const upper = s => s.toUpperCase();
        compare(PageLogic.curveLabel(catalog[0], upper), "QUICK START, GENTLE STOP");
        compare(PageLogic.curveLabel(catalog[2], upper), "Mi curva");
        compare(PageLogic.curveLabel(null, upper), "");
    }

    function test_styleText() {
        compare(PageLogic.styleText(null, tr), "");
        compare(PageLogic.styleText({ kind: "popin", label: "Pop in", percent: 80, direction: "", known: true }, tr), "Pop in 80%");
        compare(PageLogic.styleText({ kind: "slide", label: "Slide", percent: null, direction: "left", known: true }, tr), "Slide from the left");
        compare(PageLogic.styleText({ kind: "gnomed", label: "GNOME style", percent: null, direction: "", known: true }, tr), "GNOME style");
        compare(PageLogic.styleText({ kind: "", label: "", percent: null, direction: "", known: false, raw: "wobble 3" }, tr), "Not recognized: wobble 3");
    }

    function test_summaryText() {
        const parts = {
            enabled: true,
            style: { kind: "popin", label: "Pop in", percent: 80, direction: "", known: true, raw: "popin 80%" },
            durationMs: 300,
            spring: false,
            curve: { name: "emphasizedDecel", label: "Quick start, gentle stop", known: true }
        };
        compare(PageLogic.summaryText(parts, catalog, tr, 0), "Pop in 80% · 300 ms · Quick start, gentle stop");
        compare(PageLogic.summaryText(Object.assign({}, parts, { enabled: false }), catalog, tr, 0), "No animation");
        compare(PageLogic.summaryText(Object.assign({}, parts, { style: null }), catalog, tr, 0), "300 ms · Quick start, gentle stop");
        const spring = Object.assign({}, parts, { style: null, durationMs: null, spring: true, curve: { name: "ii_spring_soft", label: "Soft spring", known: true } });
        compare(PageLogic.summaryText(spring, catalog, tr, 647), "≈ 650 ms (set by the spring) · Soft spring");
        const unknown = Object.assign({}, parts, { style: null, curve: { name: "mystery", label: "Not recognized: %1", known: false } });
        compare(PageLogic.summaryText(unknown, catalog, tr, 0), "300 ms · Not recognized: mystery");
        compare(PageLogic.summaryText(Object.assign({}, parts, { style: null, curve: { name: "ii_curve_1", label: "", known: true } }), catalog, tr, 0), "300 ms · Mi curva");
        compare(PageLogic.summaryText(null, catalog, tr, 0), "");
    }

    function test_styleChoices_adds_none_only_while_used() {
        const options = [{ kind: "popin", label: "Pop in", description: "d", percent: true, directions: [] }];
        compare(PageLogic.styleChoices(options, { kind: "popin", known: true }).map(c => c.kind), ["popin"]);
        compare(PageLogic.styleChoices(options, { kind: "none", known: true }).map(c => c.kind), ["none", "popin"]);
        compare(PageLogic.styleChoices([], { kind: "none", known: true }), []);
    }

    function test_restyle() {
        const choices = [
            { kind: "slide", percent: false, directions: ["top", "bottom", "left", "right"] },
            { kind: "popin", percent: true, directions: [] },
            { kind: "gnomed", percent: false, directions: [] }
        ];
        const popin = { kind: "popin", percent: 80, direction: "", known: true };
        compare(PageLogic.restyle("windowsIn", popin, { percent: 60 }, choices, 80), "popin 60%");
        compare(PageLogic.restyle("windowsIn", popin, { kind: "slide" }, choices, 80), "slide");
        compare(PageLogic.restyle("windowsIn", { kind: "slide", percent: null, direction: "", known: true }, { direction: "left" }, choices, 80), "slide left");
        compare(PageLogic.restyle("windowsIn", { kind: "slide", percent: null, direction: "left", known: true }, { kind: "popin" }, choices, 80), "popin 80%");
        compare(PageLogic.restyle("windowsIn", { kind: "slide", percent: null, direction: "left", known: true }, { kind: "gnomed" }, choices, 80), "gnomed");
    }

    function test_withField_copies_the_card() {
        const value = { enabled: true, speed: 3, curve: "default", style: "popin 80%" };
        const changed = PageLogic.withField(value, "speed", 2.5);
        compare(changed, { enabled: true, speed: 2.5, curve: "default", style: "popin 80%" });
        compare(value.speed, 3);
    }

    function test_presetChoices() {
        const presets = [{ value: "default", label: "Default", description: "D" }, { value: "agile", label: "Agile", description: "A" }];
        compare(PageLogic.presetChoices(presets, "agile").map(p => p.value), ["default", "agile"]);
        const custom = PageLogic.presetChoices(presets, "custom");
        compare(custom.map(p => p.value), ["default", "agile", "custom"]);
        verify(custom[2].readOnly);
        verify(!custom[0].readOnly);
    }

    // The preset row is also an alias on Quick, where no cards follow it:
    // the texts never point at a place on the page.
    function test_presetChoices_custom_text_names_no_position() {
        const custom = PageLogic.presetChoices([], "custom")[0];
        verify(custom.description.length > 0);
        verify(!/\b(below|above|this page)\b/i.test(custom.description), custom.description);
    }

    function test_undoPlan_writes_managed_cards_and_resets_the_rest() {
        const plan = PageLogic.undoPlan([
            { key: "animation.windowsIn", managed: true, value: { enabled: true, speed: 2.5, curve: "default", style: "" } },
            { key: "animation.border", managed: false, value: { enabled: true, speed: 10, curve: "emphasizedDecel", style: "" } }
        ]);
        compare(plan, [
            { key: "animation.windowsIn", action: "write", value: { enabled: true, speed: 2.5, curve: "default", style: "" } },
            { key: "animation.border", action: "reset" }
        ]);
        compare(PageLogic.undoPlan(null), []);
    }

    function test_newCurveName_follows_the_backend_rule() {
        compare(PageLogic.newCurveName([]), "ii_curve_1");
        compare(PageLogic.newCurveName(["ii_curve_1", "ii_curve_2", "default"]), "ii_curve_3");
        verify(/^ii_[a-z0-9_]{1,32}$/.test(PageLogic.newCurveName(["ii_curve_1"])));
    }

    function test_curvesWith() {
        const list = [
            { name: "ii_curve_1", type: "bezier", points: [0.2, 0, 0, 1], label: "One", group: "user", builtin: false },
            { name: "ii_curve_2", type: "spring", mass: 1, stiffness: 100, damping: 10, label: "Two", group: "user", builtin: false }
        ];
        // Add, keeping the others as stored curves (no group/builtin).
        compare(PageLogic.curvesWith(list, "ii_curve_3", { type: "bezier", points: [0, 0, 1, 1], label: "Three" }), [
            { name: "ii_curve_1", type: "bezier", label: "One", points: [0.2, 0, 0, 1] },
            { name: "ii_curve_2", type: "spring", label: "Two", mass: 1, stiffness: 100, damping: 10 },
            { name: "ii_curve_3", type: "bezier", label: "Three", points: [0, 0, 1, 1] }
        ]);
        // Replace in place.
        compare(PageLogic.curvesWith(list, "ii_curve_1", { type: "bezier", points: [0.5, 0, 0.5, 1], label: "Uno" })[0],
            { name: "ii_curve_1", type: "bezier", label: "Uno", points: [0.5, 0, 0.5, 1] });
        // Remove.
        compare(PageLogic.curvesWith(list, "ii_curve_1", null).map(c => c.name), ["ii_curve_2"]);
    }

    function test_labelProblem_is_the_backend_rule() {
        compare(PageLogic.labelProblem("Mi curva"), "");
        compare(PageLogic.labelProblem("  "), "The name cannot be empty");
        compare(PageLogic.labelProblem("x".repeat(41)), "The name is longer than 40 characters");
    }
}
