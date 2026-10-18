pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "AuthenticatorModel.js" as Model

Singleton {
    id: root
    property var accounts: []
    property var codes: ({})
    property bool loaded: false
    property bool viewing: false
    property bool loadError: false
    property bool codeError: false
    property bool loadTimedOut: false
    property bool loadPending: false
    property bool codeTimedOut: false
    property bool loadAwaiting: false
    property bool codeAwaiting: false
    property string codeWindow: ""
    property real codeRequestedAt: -1
    property real codeGeneratedAt: -1
    readonly property var entries: Model.displayEntries(root.accounts)
    property int tick: 0
    property int saveRevision: 0
    property bool savePending: false
    property var savePayload: []
    property int codeRevision: 0
    property int codeRunningRevision: 0
    property bool codePending: false
    property var codePayload: []
    readonly property string python: "/usr/bin/python"
    readonly property string script: `${Quickshell.shellPath("scripts")}/authenticator.py`

    function key(account) { return Model.key(account) }
    function codeFor(entry) {
        root.tick;
        if (!root.viewing || root.codeError) return "";
        return Model.currentCode(entry, root.codes, root.codeGeneratedAt, Date.now() / 1000);
    }
    function retry() {
        if (!root.viewing) return;
        if (root.loadError || !root.loaded) {
            if (loadProcess.running) { root.loadPending = true; return; }
            root.loaded = false;
            root.loadError = false;
            root.loadTimedOut = false;
            root.loadAwaiting = true;
            loadProcess.running = true;
        } else root.refreshCodes();
    }
    function secondsRemaining(account) { root.tick; return account.period - (Math.floor(Date.now() / 1000) % account.period) }
    function uri(account) {
        const label = encodeURIComponent(`${account.issuer}:${account.account}`)
        return `otpauth://totp/${label}?secret=${account.secret}&issuer=${encodeURIComponent(account.issuer)}&algorithm=${account.algorithm}&digits=${account.digits}&period=${account.period}`
    }
    function add(account) {
        return addMany([account])
    }
    function validAccount(account) {
        return Model.normalizeAccount(account) !== null
    }
    function addMany(newAccounts) {
        if (!Array.isArray(newAccounts)) return 0
        let changed = false
        let changedCount = 0
        newAccounts.forEach(account => {
            account = Model.normalizeAccount(account)
            if (!account) return
            const duplicate = accounts.findIndex(item => key(item) === key(account))
            if (duplicate >= 0) accounts[duplicate] = account
            else accounts.push(account)
            changed = true
            changedCount += 1
        })
        if (!changed) return 0
        root.accounts = accounts.slice()
        save()
        refreshCodes()
        return changedCount
    }
    function remove(index) {
        if (index < 0 || index >= accounts.length) return
        accounts.splice(index, 1)
        root.accounts = accounts.slice()
        save()
        refreshCodes()
    }
    function save() {
        root.saveRevision += 1
        root.savePayload = root.accounts.slice()
        if (saveProcess.running) { root.savePending = true; return }
        saveProcess.stdinEnabled = true
        saveProcess.running = true
    }
    function refreshCodes() {
        root.codeRevision += 1
        if (!root.viewing || root.loadError) return
        if (!accounts.length) { root.codes = ({}); root.codePending = false; root.codeError = false; return }
        if (codeProcess.running) { root.codePending = true; return }
        root.codePending = false
        root.codeRunningRevision = root.codeRevision
        root.codePayload = root.accounts.slice()
        root.codeRequestedAt = Date.now() / 1000
        root.codeWindow = Model.windowSignature(root.accounts, root.codeRequestedAt)
        root.codeError = false
        root.codeTimedOut = false
        root.codeAwaiting = true
        codeProcess.stdinEnabled = true
        codeProcess.running = true
    }
    function parseUri(uri) {
        try {
            const parsed = String(uri).trim()
            if (parsed.length > 4096 || !parsed.toLowerCase().startsWith("otpauth://totp/")) return null
            const parts = parsed.split("?")
            const label = decodeURIComponent(parts[0].slice("otpauth://totp/".length))
            const query = {}
            parts.slice(1).join("?").split("&").forEach(pair => {
                const values = pair.split("=")
                if (values.length >= 2) query[decodeURIComponent(values[0])] = decodeURIComponent(values.slice(1).join("="))
            })
            const secret = (query.secret || "").replace(/\s/g, "").toUpperCase()
            const digits = Number(query.digits || 6)
            const period = Number(query.period || 30)
            const algorithm = (query.algorithm || "SHA1").toUpperCase()
            const labelParts = label.split(":")
            const account = labelParts.length > 1 ? labelParts.slice(1).join(":") : label
            const result = { issuer: query.issuer || (labelParts.length > 1 ? labelParts[0] : ""), account, secret, algorithm, digits, period }
            return root.validAccount(result) ? result : null
        } catch (error) { return null }
    }

    onViewingChanged: {
        if (root.viewing) {
            root.tick += 1;
            if (!root.loaded || root.loadError) root.retry();
            else root.refreshCodes();
        } else {
            root.codeRevision += 1;
            root.codePending = false;
            root.codes = ({});
            root.codeGeneratedAt = -1;
            root.loadPending = false;
            root.loadAwaiting = false;
            root.codeAwaiting = false;
            loadProcess.running = false;
            codeProcess.running = false;
            // A late process result is discarded by its revision; never publish it closed.
        }
    }

    Process {
        id: loadProcess
        command: ["secret-tool", "lookup", "application", "illogical-impulse-authenticator"]
        stdout: StdioCollector { id: loadOutput }
        stderr: StdioCollector { id: loadErrors }
        onRunningChanged: {
            if (running) return;
            // FailedToStart does not emit exited; defer so normal exits finish first.
            Qt.callLater(() => {
                if (root.viewing && root.loadAwaiting && !loadProcess.running && !root.loadPending) {
                    root.loadAwaiting = false;
                    root.loaded = true;
                    root.loadError = true;
                }
            });
        }
        onExited: exitCode => {
            root.loadAwaiting = false;
            if (root.loadPending && root.viewing) {
                root.loadPending = false;
                root.retry();
                return;
            }
            if (!root.viewing) { root.loaded = false; return; }
            try {
                // secret-tool lookup exits 1 with no output when no item exists.
                if (root.loadTimedOut || (exitCode !== 0 && !(exitCode === 1 && !loadOutput.text && !loadErrors.text))) throw new Error("Lookup failed");
                root.accounts = Model.loadAccounts(loadOutput.text);
                root.loadError = false;
            } catch (error) {
                root.accounts = [];
                root.loadError = true;
            }
            root.loaded = true;
            if (root.viewing && !root.loadError) root.refreshCodes();
        }
    }
    Process {
        id: saveProcess
        command: ["secret-tool", "store", "--label=Authenticator TOTP Safe Storage", "application", "illogical-impulse-authenticator"]
        onRunningChanged: {
            if (running) {
                write(JSON.stringify(root.savePayload))
                stdinEnabled = false
            }
        }
        onExited: {
            if (root.savePending) {
                root.savePending = false
                saveProcess.stdinEnabled = true
                saveProcess.running = true
            }
        }
    }
    Process {
        id: codeProcess
        command: [root.python, root.script, "totps"]
        onRunningChanged: {
            if (running) {
                write(JSON.stringify(root.codePayload))
                stdinEnabled = false
            } else {
                Qt.callLater(() => {
                    if (root.viewing && root.codeAwaiting && !codeProcess.running) {
                        root.codeAwaiting = false;
                        root.codePayload = [];
                        root.codes = ({});
                        root.codeGeneratedAt = -1;
                        root.codeError = true;
                    }
                });
            }
        }
        stdout: StdioCollector { id: codeOutput }
        stderr: StdioCollector {}
        onExited: exitCode => {
            root.codeAwaiting = false;
            if (root.viewing && root.codeRunningRevision === root.codeRevision) {
                try {
                    if (exitCode !== 0 || root.codeTimedOut) throw new Error("Generation failed");
                    const values = JSON.parse(codeOutput.text || "{}");
                    if (!values || typeof values !== "object" || Array.isArray(values)) throw new Error("Invalid codes");
                    const codes = Object.create(null);
                    root.entries.forEach(entry => {
                        if (typeof values[entry.key] !== "string" || !new RegExp("^[0-9]{" + entry.digits + "}$").test(values[entry.key])) throw new Error("Missing code");
                        codes[entry.key] = values[entry.key];
                    });
                    root.codes = codes;
                    root.codeGeneratedAt = root.codeRequestedAt;
                    root.codeError = false;
                } catch (error) {
                    root.codes = ({});
                    root.codeGeneratedAt = -1;
                    root.codeError = true;
                }
            }
            root.codePayload = [];
            if (root.codePending && root.viewing) {
                root.codePending = false
                root.refreshCodes()
            }
        }
    }
    Timer {
        interval: 100
        running: root.loaded && root.viewing && !root.loadError
        repeat: true
        onTriggered: {
            root.tick += 1;
            if (root.accounts.length && Model.windowSignature(root.accounts, Date.now() / 1000) !== root.codeWindow) root.refreshCodes();
        }
    }
    Timer {
        interval: 15000
        running: root.loadAwaiting
        onTriggered: { root.loadTimedOut = true; loadProcess.running = false; }
    }
    Timer {
        interval: 5000
        running: root.codeAwaiting
        onTriggered: { root.codeTimedOut = true; codeProcess.running = false; }
    }
}
