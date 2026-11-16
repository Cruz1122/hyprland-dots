pragma Singleton
pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

// Voice dictation: one press records, a pause (or a second press) ends it,
// the text is typed into the focused window. Transcription is local, by a
// whisper.cpp server this service starts on demand and stops when idle, so
// the model does not hold GPU memory while unused.
Singleton {
    id: root

    // "idle" | "listening" | "transcribing" | "done" | "error"
    property string phase: "idle"
    readonly property bool busy: phase === "listening" || phase === "transcribing"
    // Microphone level 0..1 and its recent history (newest last), for meters.
    property real level: 0
    readonly property int historyLength: 24
    // Seconds between two level samples; matches CHUNK_SECONDS in dictate.py.
    readonly property real sampleInterval: 0.05
    property list<real> levels: []
    property string lastText: ""
    // Recording on hold: nothing said meanwhile is kept, and it does not end by itself.
    property bool paused: false
    property string errorText: ""
    // Seconds spent listening, for the timer readout.
    property int elapsedSeconds: 0

    readonly property string home: FileUtils.trimFileProtocol(Directories.home)
    readonly property string installDir: `${home}/.local/share/ii-dictation/whisper.cpp`
    readonly property string serverBinary: `${installDir}/build/bin/whisper-server`
    readonly property string modelPath: `${installDir}/models/ggml-${Config.options.dictation.model}.bin`
    readonly property string userDir: `${home}/.config/illogical-impulse/dictation`
    readonly property string script: FileUtils.trimFileProtocol(`${Directories.scriptPath}/dictation/dictate.py`)
    readonly property int port: 8177

    function toggle() {
        if (phase === "listening") {
            finish();
            return;
        }
        if (phase === "transcribing")
            return;
        start();
    }

    function start() {
        root.errorText = "";
        root.level = 0;
        root.levels = [];
        root.elapsedSeconds = 0;
        root.paused = false;
        root.phase = "listening";
        // The model loads while the user is still talking.
        serverProc.running = true;
        unloadTimer.stop();
        lingerTimer.stop();
        recordProc.running = true;
    }

    // End the recording now and transcribe what was said.
    function finish() {
        if (recordProc.running)
            Quickshell.execDetached(["kill", "-USR1", String(recordProc.processId)]);
    }

    function togglePause() {
        if (phase === "listening" && recordProc.running)
            Quickshell.execDetached(["kill", "-USR2", String(recordProc.processId)]);
    }

    function cancel() {
        if (recordProc.running)
            Quickshell.execDetached(["kill", "-TERM", String(recordProc.processId)]);
    }

    function fail(message) {
        root.errorText = message;
        root.phase = "error";
        lingerTimer.interval = 4000;
        lingerTimer.restart();
    }

    function handleMessage(line) {
        let message;
        try {
            message = JSON.parse(line);
        } catch (error) {
            console.warn("[Dictation] Unreadable line from dictate.py:", line);
            return;
        }
        if (message.level !== undefined) {
            root.level = message.level;
            const history = root.levels.slice(-(root.historyLength - 1));
            history.push(message.level);
            root.levels = history;
        } else if (message.paused !== undefined) {
            root.paused = message.paused;
        } else if (message.state === "transcribing") {
            root.paused = false;
            root.phase = "transcribing";
        } else if (message.text !== undefined) {
            root.lastText = message.text;
            if (message.text.length > 0) {
                // Trailing space so consecutive dictations do not run together.
                Quickshell.execDetached(["wtype", "--", `${message.text} `]);
                root.phase = "done";
                lingerTimer.interval = 700;
            } else {
                root.errorText = Translation.tr("Didn't catch anything");
                root.phase = "error";
                lingerTimer.interval = 1800;
            }
            lingerTimer.restart();
        } else if (message.error !== undefined) {
            root.fail(message.error);
        }
    }

    Process {
        id: recordProc
        command: [
            "python3", root.script,
            "--server", `http://127.0.0.1:${root.port}`,
            "--language", Config.options.dictation.language,
            "--glossary", `${root.userDir}/glossary.txt`,
            "--replacements", `${root.userDir}/replacements.tsv`,
            "--silence", String(Config.options.dictation.silenceSeconds),
        ]
        stdout: SplitParser {
            onRead: line => root.handleMessage(line)
        }
        onExited: (exitCode, exitStatus) => {
            root.paused = false;
            if (root.busy) // cancelled, or died without reporting
                root.phase = "idle";
            unloadTimer.restart();
        }
    }

    Process {
        id: serverProc
        command: [
            root.serverBinary,
            "--model", root.modelPath,
            "--host", "127.0.0.1",
            "--port", String(root.port),
            "--language", Config.options.dictation.language,
            "--threads", "4",
        ]
        onExited: (exitCode, exitStatus) => {
            // 0 / signalled are our own shutdowns.
            if (exitCode !== 0 && root.busy)
                root.fail(Translation.tr("The speech model could not start"));
        }
    }

    Timer { // Seconds counter while listening
        interval: 1000
        repeat: true
        running: root.phase === "listening" && !root.paused
        onTriggered: root.elapsedSeconds += 1
    }

    Timer { // How long a result or error stays on screen
        id: lingerTimer
        onTriggered: {
            if (!root.busy)
                root.phase = "idle";
        }
    }

    Timer { // Free the GPU memory after a while without dictating
        id: unloadTimer
        interval: Math.max(1, Config.options.dictation.keepLoadedMinutes) * 60000
        onTriggered: {
            if (!root.busy)
                serverProc.running = false;
        }
    }

    IpcHandler {
        target: "dictation"

        function toggle(): void {
            root.toggle();
        }
        function pause(): void {
            root.togglePause();
        }
        function cancel(): void {
            root.cancel();
        }
    }

    GlobalShortcut {
        name: "dictationToggle"
        description: "Starts a dictation, or ends the one in progress"
        onPressed: root.toggle()
    }
}
