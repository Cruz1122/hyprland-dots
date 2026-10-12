pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

Singleton {
    id: root

    readonly property int schemaVersion: 1
    readonly property var categories: [
        { id: "foundation", name: "Foundation", icon: "foundation" },
        { id: "appearance", name: "Appearance", icon: "palette" },
        { id: "capture", name: "Capture", icon: "video_camera_front" },
        { id: "system", name: "System", icon: "settings_applications" }
    ]

    readonly property var settings: [
        {
            key: "appearance.transparency.enable",
            title: "Transparency",
            description: "Enable transparent surfaces where supported by the shell.",
            category: "appearance",
            type: "boolean",
            backend: "config",
            immediate: true,
            defaultValue: false
        },
        {
            key: "appearance.transparency.backgroundTransparency",
            title: "Background transparency",
            description: "Controls the global background transparency amount.",
            category: "appearance",
            type: "number",
            backend: "config",
            immediate: true,
            min: 0,
            max: 1,
            defaultValue: 0.11
        },
        {
            key: "audio.protection.enable",
            title: "Ear protection",
            description: "Prevent sudden unsafe volume increases.",
            category: "system",
            type: "boolean",
            backend: "config",
            immediate: true,
            defaultValue: true
        },
        {
            key: "screenRecord.savePath",
            title: "Recording save path",
            description: "Directory used by screen recordings.",
            category: "capture",
            type: "path",
            backend: "config",
            immediate: true,
            defaultValue: "~/Videos"
        },
        {
            key: "screenRecord.fileFormat",
            title: "Recording format",
            description: "Container extension used for new recordings.",
            category: "capture",
            type: "enum",
            backend: "config",
            immediate: true,
            options: ["mp4", "mkv", "webm"],
            defaultValue: "mp4"
        },
        {
            key: "screenRecord.fps",
            title: "Recording FPS",
            description: "Frame rate passed to wf-recorder.",
            category: "capture",
            type: "number",
            backend: "config",
            immediate: true,
            min: 1,
            max: 240,
            defaultValue: 60
        },
        {
            key: "screenRecord.pixelFormat",
            title: "Pixel format",
            description: "Pixel format passed to wf-recorder.",
            category: "capture",
            type: "enum",
            backend: "config",
            immediate: true,
            options: ["yuv420p", "nv12", "auto"],
            defaultValue: "yuv420p"
        },
        {
            key: "screenRecord.recordAudioByDefault",
            title: "Record audio by default",
            description: "Recorder buttons include system audio unless explicitly disabled.",
            category: "capture",
            type: "boolean",
            backend: "config",
            immediate: true,
            defaultValue: true
        },
        {
            key: "screenRecord.fullscreenUsesFocusedMonitor",
            title: "Fullscreen uses focused monitor",
            description: "Fullscreen recording targets the focused monitor instead of all outputs.",
            category: "capture",
            type: "boolean",
            backend: "config",
            immediate: true,
            defaultValue: true
        },
        {
            key: "screenRecord.barButtonAction",
            title: "Bar recording button action",
            description: "Action executed by the bar recording utility button.",
            category: "capture",
            type: "enum",
            backend: "config",
            immediate: true,
            options: ["fullscreen", "region", "pause", "stop"],
            defaultValue: "fullscreen"
        },
        {
            key: "screenRecord.audioSource",
            title: "Audio source",
            description: "Which audio source is recorded with the video.",
            category: "capture",
            type: "enum",
            backend: "config",
            immediate: true,
            options: ["system", "mic", "both", "none"],
            defaultValue: "system"
        },
        {
            key: "screenRecord.micDevice",
            title: "Microphone device",
            description: "PipeWire node name of the microphone to use. Empty uses the default source.",
            category: "capture",
            type: "string",
            backend: "config",
            immediate: true,
            defaultValue: ""
        },
        {
            key: "screenRecord.systemAudioDevice",
            title: "System audio device",
            description: "PipeWire node name of the system audio output to record. Empty uses the default sink.",
            category: "capture",
            type: "string",
            backend: "config",
            immediate: true,
            defaultValue: ""
        }
    ]

    function settingByKey(key) {
        for (let i = 0; i < root.settings.length; i++) {
            if (root.settings[i].key === key) return root.settings[i];
        }
        return null;
    }

    function settingsForCategory(categoryId) {
        return root.settings.filter(setting => setting.category === categoryId);
    }
}
