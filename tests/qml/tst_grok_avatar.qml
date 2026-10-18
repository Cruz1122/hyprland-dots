import QtQuick
import QtTest

TestCase {
    id: testCase
    name: "GrokAvatarRenderer"
    when: windowShown
    visible: true
    width: 64
    height: 64

    Image {
        id: avatar
        anchors.fill: parent
        asynchronous: false
        cache: false
    }

    property var motionCache: null

    Item {
        id: motionClockHost
        width: 1
        height: 1

        Component.onCompleted: if (testCase.motionCache)
            testCase.motionCache.registerClock(motionClockHost)
        Component.onDestruction: if (testCase.motionCache)
            testCase.motionCache.unregisterClock(motionClockHost)

        FrameAnimation {
            running: true
            onTriggered: if (testCase.motionCache)
                testCase.motionCache.updateClock(elapsedTime)
        }
    }

    Loader {
        id: motionCacheLoader
        source: Qt.resolvedUrl(
            "../../config/quickshell/ii/modules/common/GrokAvatarMotionCache.qml"
        )
        asynchronous: false
        onLoaded: {
            testCase.motionCache = motionCacheLoader.item;
            testCase.motionCache.registerClock(motionClockHost);
        }
    }

    function test_all_original_grok_svgs_load_in_qt() {
        const shapes = [
            "arch", "bean", "blob", "capsule", "cloud", "clover", "crystal",
            "cylinder", "dome", "egg", "flower", "gem", "heart", "hex",
            "house", "leaf", "pebble", "shield", "sparkle", "square",
            "squircle", "star", "tablet", "teardrop", "wedge"
        ];

        for (const shape of shapes) {
            const templateUrl = Qt.resolvedUrl(
                "../../config/quickshell/ii/assets/grok-avatar-templates/" + shape + ".svg.tmpl"
            );
            const request = new XMLHttpRequest();
            request.open("GET", templateUrl, false);
            request.send();
            verify(request.readyState === XMLHttpRequest.DONE, "could not read Grok SVG: " + shape);
            verify(request.status === 0 || request.status === 200, "bad template response: " + shape);

            const template = request.responseText.trim();
            verify(template.length > 0, "empty Grok SVG: " + shape);
            verify(template.includes("__LIGHT__") && template.includes("__DARK__"));
            const originalSvg = decodeURIComponent(template);
            const styleStart = originalSvg.indexOf("<style>");
            const styleEnd = originalSvg.indexOf("</style>", styleStart) + "</style>".length;
            verify(styleStart >= 0 && styleEnd > styleStart, "missing Grok color style: " + shape);
            const paths = originalSvg.slice(0, styleStart) + originalSvg.slice(styleEnd);

            for (const ink of ["#2A92FE", "#0E74E0"]) {
                const coloredSvg = paths.replace("var(--grok-bot-still-ink)", ink);
                verify(!coloredSvg.includes("var(--grok-bot-still-ink)"), "unresolved SVG ink: " + shape);
                verify(coloredSvg.includes('fill="' + ink + '"'), "literal ink missing: " + shape);
                avatar.source = "";
                tryCompare(avatar, "status", Image.Null);
                avatar.source = "data:image/svg+xml," + encodeURIComponent(coloredSvg);
                tryCompare(avatar, "status", Image.Ready, 5000);
                verify(avatar.sourceSize.width > 0, "Qt did not decode Grok SVG: " + shape);
                if (shape === "cloud") {
                    const rendered = grabImage(avatar);
                    let hasPaletteInk = false;
                    for (let y = 0; y < rendered.height && !hasPaletteInk; y++) {
                        for (let x = 0; x < rendered.width; x++) {
                            const pixel = String(rendered.pixel(x, y)).toLowerCase();
                            if (pixel === ink.toLowerCase() || pixel.endsWith(ink.slice(1).toLowerCase())) {
                                hasPaletteInk = true;
                                break;
                            }
                        }
                    }
                    verify(hasPaletteInk, "Qt did not paint the Grok ink " + ink);
                }
            }
        }
    }

    function test_native_motion_svg_frames_load_in_qt() {
        const sequences = [
            "blob-violet", "heart-red", "sparkle-magenta", "teardrop-black",
            "hex-green", "star-yellow", "cloud-blue", "tablet-violet"
        ];
        const states = [
            "neutral", "attentive", "surprised", "excited", "happy", "laughing",
            "angry", "sad", "scared", "suspicious", "confused", "curious",
            "proud", "shy", "unimpressed", "sleepy"
        ];
        const frameIndexes = [0, 23, 45];

        for (const sequence of sequences) {
            for (const state of states) {
                for (const frameIndex of frameIndexes) {
                    const frameUrl = Qt.resolvedUrl(
                        "../../config/quickshell/ii/assets/grok-avatar-animations/"
                        + sequence + "/" + state + "/frame-" + String(frameIndex).padStart(3, "0") + ".svg"
                    );
                    avatar.source = "";
                    tryCompare(avatar, "status", Image.Null);
                    avatar.source = frameUrl;
                    tryCompare(avatar, "status", Image.Ready, 5000);
                    verify(avatar.sourceSize.width > 0, "Qt did not decode native frame: " + frameUrl);
                    verify(avatar.sourceSize.height > 0, "native frame has no height: " + frameUrl);
                }
            }
        }
    }

    function test_motion_ping_pong_loop_returns_to_first_frame() {
        const frameCount = 181;
        let frame = 0;
        let direction = 1;
        const cycleLength = (frameCount - 1) * 2;

        for (let step = 0; step < cycleLength; step++) {
            const nextFrame = frame + direction;
            if (nextFrame >= frameCount - 1) {
                frame = frameCount - 1;
                direction = -1;
            } else if (nextFrame <= 0) {
                frame = 0;
                direction = 1;
            } else {
                frame = nextFrame;
            }
        }

        compare(frame, 0);
        compare(direction, 1);
    }

    function test_interpolated_motion_svg_frames_load_in_qt() {
        const sequences = [
            "blob-violet", "heart-red", "sparkle-magenta", "teardrop-black",
            "hex-green", "star-yellow", "cloud-blue", "tablet-violet"
        ];
        const states = ["neutral", "attentive", "curious", "sleepy"];
        const frameIndexes = [0, 1, 2, 4, 90, 179, 180];

        for (const sequence of sequences) {
            for (const state of states) {
                for (const frameIndex of frameIndexes) {
                    const frameUrl = Qt.resolvedUrl(
                        "../../config/quickshell/ii/assets/grok-avatar-animations-interpolated/"
                        + sequence + "/" + state + "/frame-" + String(frameIndex).padStart(3, "0") + ".svg"
                    );
                    avatar.source = "";
                    tryCompare(avatar, "status", Image.Null);
                    avatar.source = frameUrl;
                    tryCompare(avatar, "status", Image.Ready, 5000);
                    verify(avatar.sourceSize.width > 0, "Qt did not decode interpolated frame: " + frameUrl);
                    verify(avatar.sourceSize.height > 0, "interpolated frame has no height: " + frameUrl);
                }
            }
        }
    }

    function test_motion_cache_clock_is_scene_synchronized() {
        const before = motionCache.elapsedTime;
        wait(300);
        verify(motionCache.elapsedTime > before);
        verify(motionCache.currentCycleStep >= 0);
        verify(motionCache.currentCycleStep < motionCache.cycleStepCount);
    }
}
