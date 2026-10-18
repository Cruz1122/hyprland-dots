pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick

// One compositor-synchronised clock for all Grok avatars. The generated SVGs
// are reused through Qt Quick's shared Image cache; individual avatars do not
// create their own animation timers or hidden per-frame preloaders.
Item {
    id: root

    visible: false
    width: 0
    height: 0

    readonly property int frameCount: 181
    readonly property int frameIntervalMs: 25
    readonly property int cycleStepCount: (frameCount - 1) * 2
    // 38 * 1.45 * 2 is the largest current native layer. A fixed texture size
    // lets the cache share decoded images between the 26 px bar and 38 px
    // notification avatars.
    readonly property int textureSize: 112
    property var clockOwner: null
    property int activeAvatarCount: 0
    property int lastClockFrameStep: -1

    // A FrameAnimation hosted by one visible GrokAvatar publishes this clock.
    // A singleton itself is not attached to a scene graph, so it cannot own
    // the compositor callback directly.
    property real elapsedTime: 0
    readonly property int currentCycleStep: Math.floor(
        elapsedTime * 1000 / frameIntervalMs
    ) % cycleStepCount

    function registerClock(owner) {
        if (clockOwner === null || !clockOwner) {
            clockOwner = owner;
            lastClockFrameStep = -1;
            return true;
        }
        return clockOwner === owner;
    }

    function registerAvatar() {
        activeAvatarCount += 1;
    }

    function unregisterClock(owner) {
        if (clockOwner === owner) {
            clockOwner = null;
            lastClockFrameStep = -1;
        }
    }

    function unregisterAvatar(owner) {
        activeAvatarCount = Math.max(0, activeAvatarCount - 1);
        unregisterClock(owner);
        if (activeAvatarCount === 0) {
            elapsedTime = 0;
            lastClockFrameStep = -1;
        }
    }

    function updateClock(nextElapsedTime) {
        if (clockOwner === null)
            return;

        // FrameAnimation is compositor-synchronised at the monitor refresh
        // rate, but the generated assets advance every 25 ms. Avoid waking
        // every avatar's bindings on all 144 callbacks when the visible
        // sample has not changed yet.
        const frameStep = Math.floor(nextElapsedTime * 1000 / frameIntervalMs);
        if (frameStep === lastClockFrameStep)
            return;
        lastClockFrameStep = frameStep;
        elapsedTime = nextElapsedTime;
    }

    function frameSource(animationKey, stateKey, frameIndex) {
        return Qt.resolvedUrl(
            `../../assets/grok-avatar-animations-interpolated/${animationKey}/${stateKey}/frame-${String(frameIndex).padStart(3, "0")}.svg`
        );
    }
}
