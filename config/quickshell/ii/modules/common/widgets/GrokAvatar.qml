pragma ComponentBehavior: Bound

import qs.modules.common
import QtQuick
import Qt5Compat.GraphicalEffects

// Render Grok's actual avatar output. A supplied photo wins; otherwise a
// captured native-motion SVG sequence is used when this shape/color pair is
// available. The still SVG generated from Grok's renderer remains the generic
// fallback, and missing avatar data uses Grok's neutral white circle.
Item {
    id: root

    property var bot: null
    property string avatarPhoto: bot?.avatarPhoto ?? bot?.avatarDataUrl ?? ""
    property string avatarSvg: Appearance.m3colors.darkmode
        ? (bot?.avatarSvgDark ?? bot?.avatarSvg ?? "")
        : (bot?.avatarSvg ?? "")
    property string avatarShape: bot?.avatarShape ?? ""
    property string avatarColor: bot?.avatarColor ?? ""
    property string nativeAnimationKey: `${avatarShape}-${avatarColor}`
    // The roster does not persist an animation state. Callers may provide one
    // for interaction feedback; the default stays neutral like Grok's app.
    property string nativeAnimationState: bot?.avatarAnimationState ?? "neutral"
    readonly property var nativeAnimationStates: [
        "neutral", "attentive", "surprised", "excited", "happy", "laughing",
        "angry", "sad", "scared", "suspicious", "confused", "curious",
        "proud", "shy", "unimpressed", "sleepy",
    ]
    readonly property string nativeAnimationStateKey: nativeAnimationStates.indexOf(nativeAnimationState) >= 0
        ? nativeAnimationState
        : "neutral"
    readonly property var nativeAnimationKeys: [
        "blob-violet",
        "heart-red",
        "sparkle-magenta",
        "teardrop-black",
        "hex-green",
        "star-yellow",
        "cloud-blue",
        "tablet-violet",
    ]
    readonly property int nativeAnimationFrameCount: GrokAvatarMotionCache.frameCount
    readonly property int nativeAnimationCycleStepCount: (nativeAnimationFrameCount - 1) * 2
    // Keep the playback duration of the native capture. The generated
    // interframes subdivide each original 100 ms interval into four 25 ms
    // samples without speeding the animation up.
    readonly property int nativeAnimationFrameInterval: GrokAvatarMotionCache.frameIntervalMs
    readonly property int nativeAnimationTextureSize: GrokAvatarMotionCache.textureSize
    readonly property bool nativeAnimationAvailable: avatarPhoto.length === 0
        && nativeAnimationKeys.indexOf(nativeAnimationKey) >= 0
    property real nativeAnimationPhaseOffset: 0
    property bool nativeAnimationClockOwner: false
    readonly property int nativeAnimationPhaseStep: Math.floor(
        nativeAnimationPhaseOffset * 1000 / nativeAnimationFrameInterval
    ) % nativeAnimationCycleStepCount
    readonly property int nativeAnimationCycleStep: (
        GrokAvatarMotionCache.currentCycleStep - nativeAnimationPhaseStep
        + nativeAnimationCycleStepCount
    ) % nativeAnimationCycleStepCount
    readonly property int nativeAnimationFrame: nativeAnimationCycleStep <= nativeAnimationFrameCount - 1
        ? nativeAnimationCycleStep
        : nativeAnimationCycleStepCount - nativeAnimationCycleStep
    readonly property int nativeAnimationDirection: nativeAnimationCycleStep < nativeAnimationFrameCount - 1
        ? 1
        : -1
    property string nativeAnimationDisplayedStateKey: "neutral"
    property string nativeAnimationTransitionFromStateKey: "neutral"
    property string nativeAnimationTransitionToStateKey: "neutral"
    property real nativeAnimationTransitionOpacity: 1
    property bool nativeAnimationTransitioning: false
    readonly property url nativeAnimationSource: nativeAnimationAvailable
        ? nativeAnimationFrameSource(nativeAnimationDisplayedStateKey, nativeAnimationFrame)
        : ""
    // The native renderer keeps intentional breathing room around its body.
    // Scale only that layer so it matches Grok's still avatar silhouette.
    readonly property real nativeAnimationVisualScale: 1.45
    property real size: 38 * scale

    implicitWidth: size
    implicitHeight: size

    function nativeAnimationFrameSource(stateKey, frameIndex) {
        return GrokAvatarMotionCache.frameSource(nativeAnimationKey, stateKey, frameIndex);
    }

    function resetNativeAnimation() {
        nativeAnimationTransitionAnimation.stop();
        nativeAnimationPhaseOffset = GrokAvatarMotionCache.elapsedTime;
        nativeAnimationDisplayedStateKey = nativeAnimationStateKey;
        nativeAnimationTransitionFromStateKey = nativeAnimationStateKey;
        nativeAnimationTransitionToStateKey = nativeAnimationStateKey;
        nativeAnimationTransitionOpacity = 1;
        nativeAnimationTransitioning = false;
    }

    function acquireNativeAnimationClock() {
        if (!nativeAnimationClockOwner && GrokAvatarMotionCache.registerClock(root))
            nativeAnimationClockOwner = true;
    }

    function startNativeAnimationStateTransition() {
        if (!nativeAnimationAvailable)
            return;

        const nextState = nativeAnimationStateKey;
        if (nativeAnimationTransitioning && nextState === nativeAnimationTransitionToStateKey)
            return;
        if (!nativeAnimationTransitioning && nextState === nativeAnimationDisplayedStateKey)
            return;

        nativeAnimationTransitionFromStateKey = nativeAnimationTransitioning
            ? nativeAnimationTransitionToStateKey
            : nativeAnimationDisplayedStateKey;
        nativeAnimationTransitionToStateKey = nextState;
        nativeAnimationTransitionOpacity = 0;
        nativeAnimationTransitioning = true;
        nativeAnimationTransitionAnimation.restart();
    }

    onBotChanged: resetNativeAnimation()
    onNativeAnimationKeyChanged: resetNativeAnimation()
    onNativeAnimationStateKeyChanged: startNativeAnimationStateTransition()

    Component.onCompleted: {
        GrokAvatarMotionCache.registerAvatar();
        acquireNativeAnimationClock();
        resetNativeAnimation();
    }

    Component.onDestruction: {
        GrokAvatarMotionCache.unregisterAvatar(root);
    }

    Connections {
        target: GrokAvatarMotionCache

        function onClockOwnerChanged() {
            root.acquireNativeAnimationClock();
        }
    }

    // FrameAnimation must be a descendant of a rendered item to receive the
    // compositor callback. Only the elected owner runs; all other avatars
    // consume the shared compositor-synchronised sample index from
    // GrokAvatarMotionCache.
    FrameAnimation {
        running: root.nativeAnimationClockOwner

        onTriggered: GrokAvatarMotionCache.updateClock(elapsedTime)
    }

    NumberAnimation {
        id: nativeAnimationTransitionAnimation
        target: root
        property: "nativeAnimationTransitionOpacity"
        from: 0
        to: 1
        duration: 220
        easing.type: Easing.OutCubic

        onFinished: {
            root.nativeAnimationDisplayedStateKey = root.nativeAnimationTransitionToStateKey;
            root.nativeAnimationTransitionFromStateKey = root.nativeAnimationTransitionToStateKey;
            root.nativeAnimationTransitioning = false;
        }
    }

    Loader {
        anchors.fill: parent
        active: root.avatarPhoto.length > 0
        sourceComponent: Item {
            anchors.fill: parent

            Rectangle {
                anchors.fill: parent
                radius: width / 2
                clip: true
                color: "transparent"

                Image {
                    anchors.fill: parent
                    source: root.avatarPhoto
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: false
                    smooth: true
                }
            }
        }
    }

    Loader {
        anchors.fill: parent
        active: root.avatarPhoto.length === 0 && root.nativeAnimationAvailable
        sourceComponent: Item {
            anchors.fill: parent

            Image {
                id: nativeAnimationFromImage
                anchors.centerIn: parent
                width: parent.width * root.nativeAnimationVisualScale
                height: parent.height * root.nativeAnimationVisualScale
                visible: root.nativeAnimationTransitioning
                opacity: 1 - root.nativeAnimationTransitionOpacity
                source: root.nativeAnimationFrameSource(
                    root.nativeAnimationTransitionFromStateKey,
                    root.nativeAnimationFrame
                )
                sourceSize: Qt.size(root.nativeAnimationTextureSize, root.nativeAnimationTextureSize)
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                cache: true
                retainWhileLoading: true
                smooth: true
                mipmap: false
            }

            ColorOverlay {
                anchors.fill: nativeAnimationFromImage
                visible: Appearance.m3colors.darkmode && root.avatarColor === "black"
                source: nativeAnimationFromImage
                color: "#FFFFFF"
            }

            Image {
                id: nativeAnimationToImage
                anchors.centerIn: parent
                width: parent.width * root.nativeAnimationVisualScale
                height: parent.height * root.nativeAnimationVisualScale
                opacity: root.nativeAnimationTransitioning
                    ? root.nativeAnimationTransitionOpacity
                    : 1
                source: root.nativeAnimationFrameSource(
                    root.nativeAnimationTransitioning
                        ? root.nativeAnimationTransitionToStateKey
                        : root.nativeAnimationDisplayedStateKey,
                    root.nativeAnimationFrame
                )
                sourceSize: Qt.size(root.nativeAnimationTextureSize, root.nativeAnimationTextureSize)
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                cache: true
                retainWhileLoading: true
                smooth: true
                mipmap: false
            }

            ColorOverlay {
                anchors.fill: nativeAnimationToImage
                visible: Appearance.m3colors.darkmode && root.avatarColor === "black"
                source: nativeAnimationToImage
                color: "#FFFFFF"
            }
        }
    }

    Loader {
        anchors.fill: parent
        active: root.avatarPhoto.length === 0 && !root.nativeAnimationAvailable && root.avatarSvg.length > 0
        sourceComponent: Image {
            anchors.fill: parent
            source: root.avatarSvg
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            cache: true
            smooth: true
        }
    }

    Rectangle {
        anchors.fill: parent
        visible: root.avatarPhoto.length === 0 && !root.nativeAnimationAvailable && root.avatarSvg.length === 0
        radius: width / 2
        color: "#FFFFFF"
    }
}
