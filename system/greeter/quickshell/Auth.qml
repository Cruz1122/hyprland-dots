pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Greetd

// Login flow over greetd. Outside greetd (no GREETD_SOCK) it runs a fake
// backend so the screen can be previewed: the password "demo" succeeds.
Singleton {
    id: root

    readonly property bool preview: !Greetd.available
    property bool busy: false
    // Shown under the password field; empty when there is nothing to say.
    property string message: ""
    property bool messageIsError: false
    // Bumped on each rejected attempt so the view can shake.
    property int failures: 0

    property string pendingPassword: ""
    property bool passwordSent: false

    signal succeeded

    function login(username, password, session) {
        if (busy || username.length === 0)
            return;
        busy = true;
        message = "";
        pendingPassword = password;
        passwordSent = false;
        pendingSession = session;
        if (preview) {
            fakeCheck.restart();
            return;
        }
        Greetd.createSession(username);
    }

    property var pendingSession: null

    function fail(text) {
        busy = false;
        pendingPassword = "";
        message = text;
        messageIsError = true;
        failures++;
    }

    function launchSession() {
        pendingPassword = "";
        const session = pendingSession;
        const env = ["XDG_SESSION_TYPE=wayland", `XDG_SESSION_DESKTOP=${session.id}`];
        if (session.desktopNames.length > 0)
            env.push(`XDG_CURRENT_DESKTOP=${session.desktopNames}`);
        if (preview) {
            console.info(`greeter preview: would launch ${JSON.stringify(session.command)} with ${JSON.stringify(env)}`);
            busy = false;
            root.succeeded();
            return;
        }
        root.succeeded();
        // quit: the greeter compositor exits with Quickshell (see hyprland.lua),
        // which hands the VT back to greetd for the user session.
        Greetd.launch(session.command, env, true);
    }

    Timer { // Fake PAM latency for the preview
        id: fakeCheck
        interval: 700
        onTriggered: {
            if (root.pendingPassword === "demo")
                root.launchSession();
            else
                root.fail(Theme.tr("Incorrect password"));
        }
    }

    Connections {
        target: root.preview ? null : Greetd

        function onAuthMessage(message, error, responseRequired, echoResponse) {
            if (responseRequired) {
                // Only the first prompt is the password. Anything else (OTP,
                // expired password) is not supported by this screen yet.
                if (root.passwordSent) {
                    Greetd.cancelSession();
                    root.fail(message.length > 0 ? message : Theme.tr("Unsupported authentication step"));
                    return;
                }
                root.passwordSent = true;
                Greetd.respond(root.pendingPassword);
                return;
            }
            // Informational PAM text (e.g. faillock warnings).
            root.message = message;
            root.messageIsError = error;
        }

        function onAuthFailure(message) {
            root.fail(Theme.tr("Incorrect password"));
        }

        function onReadyToLaunch() {
            root.launchSession();
        }

        function onError(error) {
            console.warn(`greeter: greetd error: ${error}`);
            root.fail(Theme.tr("greetd error: %1").arg(error));
        }
    }

    function poweroff() {
        run(["systemctl", "poweroff"]);
    }
    function reboot() {
        run(["systemctl", "reboot"]);
    }
    function suspend() {
        run(["systemctl", "suspend"]);
    }
    function run(command) {
        if (preview) {
            console.info(`greeter preview: would run ${command.join(" ")}`);
            return;
        }
        powerProc.command = command;
        powerProc.running = true;
    }

    Process {
        id: powerProc
        onExited: (code, status) => {
            if (code !== 0)
                root.fail(Theme.tr("Could not run %1 (exit %2)").arg(command.join(" ")).arg(code));
        }
    }
}
