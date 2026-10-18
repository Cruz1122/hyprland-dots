import QtQuick
import QtTest
import "../../config/quickshell/ii/modules/ii/bar/ResourcePresentation.js" as Presentation

TestCase {
    name: "ResourcePresentation"

    function candidates(ram, swap, cpu, gpu, hasSwap = true, hasGpu = true) {
        return [
            { id: "RAM", value: ram },
            { id: "Swap", value: swap, available: hasSwap },
            { id: "CPU", value: cpu },
            { id: "GPU", value: gpu, available: hasGpu }
        ];
    }

    function test_ranking_data() {
        return [
            { tag: "highest", input: candidates(.61, .12, .80, .93), expected: ["GPU", "CPU"] },
            { tag: "changes", input: candidates(.95, .99, .80, .93), expected: ["Swap", "RAM"] },
            { tag: "ties", input: candidates(.5, .5, .5, .5), expected: ["RAM", "Swap"] },
            { tag: "unavailable", input: candidates(.2, 1, .1, 1, false, false), expected: ["RAM", "CPU"] },
            { tag: "zero", input: candidates(0, 0, 0, 0, false, false), expected: ["RAM", "CPU"] },
            { tag: "raw-not-rounded", input: candidates(.614, .613, .615, .612), expected: ["CPU", "RAM"] },
            { tag: "invalid", input: candidates(NaN, Infinity, undefined, null), expected: [] },
            { tag: "single", input: candidates(NaN, Infinity, .3, null), expected: ["CPU"] },
            { tag: "clamped", input: candidates(-1, 2, 1, .8), expected: ["Swap", "CPU"] }
        ];
    }

    function test_ranking(data) {
        const original = data.input.map(item => item.id).join();
        const result = Presentation.topTwo(data.input);
        compare(result.map(item => item.id), data.expected);
        compare(data.input.map(item => item.id).join(), original);
        result.forEach(item => verify(item.value >= 0 && item.value <= 1));
    }

    function test_color_endpoints() {
        compare(Presentation.severity(0), 0);
        compare(Presentation.severity(.3), 0);
        fuzzyCompare(Presentation.severity(.6), .5, .0001);
        compare(Presentation.severity(.9), 1);
        compare(Presentation.severity(1), 1);
    }

    function color(value) {
        // Convert the helper's fallback hex string to a QML color for sampling.
        return Qt.tint(value, "transparent");
    }

    function test_contrast_all_transition_frames() {
        const gold = color("#F6D77A");
        const ink = color("#4A3900");
        // Material dark/light error and normal-container examples, plus extremes.
        const backgrounds = ["#ffb4ab", "#ba1a1a", "#93000a", "#ff0000",
            "#000000", "#ffffff", "#45463b", "#e2e3cf"];
        for (const endpoint of backgrounds) {
            for (let frame = 0; frame <= 300; ++frame) {
                const background = Presentation.mix(gold, color(endpoint), frame / 300);
                const foreground = color(Presentation.foreground(background, ink));
                verify(Presentation.contrast(background, foreground) >= 4.5,
                    `contrast failed: ${endpoint}, frame ${frame}`);
                const onError = color(Presentation.foreground(background, color("#ffffff")));
                verify(Presentation.contrast(background, onError) >= 4.5);
            }
        }
    }

    function test_preferred_foreground_is_preserved_when_readable() {
        const gold = color("#F6D77A");
        const ink = color("#4A3900");
        compare(Presentation.foreground(gold, ink), ink);
        const darkRed = color("#ba1a1a");
        const white = color("#ffffff");
        compare(Presentation.foreground(darkRed, white), white);
    }
}
