import QtQuick
import QtTest
import "../../config/quickshell/ii/modules/settings/backends/AudioLogic.js" as AudioLogic

TestCase {
    name: "AudioLogic"

    readonly property var hdmiA: ({ name: "hdmi", description: "HDMI", isSink: true, isStream: false, audio: {} })
    readonly property var hdmiB: ({ name: "hdmi", description: "HDMI (dup)", isSink: true, isStream: false, audio: {} })
    readonly property var speakers: ({ name: "analog", description: "", nickname: "Speakers", isSink: true, isStream: false, audio: {} })
    readonly property var stream: ({ name: "firefox", description: "Firefox", isSink: true, isStream: true, audio: {} })
    readonly property var mic: ({ name: "mic", description: "Microphone", isSink: false, isStream: false, audio: {} })
    readonly property var video: ({ name: "cam", description: "Camera", isSink: false, isStream: false, audio: null })

    function test_devices_filter_and_dedupe() {
        const nodes = [hdmiA, speakers, stream, mic, video, hdmiB];
        compare(AudioLogic.devices(nodes, true, null).map(n => n.description || n.nickname), ["HDMI", "Speakers"]);
        compare(AudioLogic.devices(nodes, true, hdmiB)[0], hdmiB, "the default wins among duplicates");
        compare(AudioLogic.devices(nodes, false, null).map(n => n.name), ["mic"]);
        compare(AudioLogic.devices(null, true, null), []);
    }

    function test_choices_and_lookup() {
        const nodes = [hdmiA, speakers, mic];
        compare(AudioLogic.choices(nodes, true, null), [
            { value: "hdmi", label: "HDMI", icon: "speaker" },
            { value: "analog", label: "Speakers", icon: "speaker" }
        ]);
        compare(AudioLogic.find(nodes, false, "mic"), mic);
        compare(AudioLogic.find(nodes, true, "mic"), null, "direction must match");
        verify(AudioLogic.isSinkEntry({ key: "audio.output" }));
        verify(!AudioLogic.isSinkEntry({ key: "audio.input" }));
    }
}
