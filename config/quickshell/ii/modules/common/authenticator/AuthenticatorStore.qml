pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root
    property var accounts: []
    property var codes: ({})
    property bool loaded: false
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

    function key(account) { return `${account.issuer}\u0000${account.account}` }
    function secondsRemaining(account) { root.tick; return account.period - (Math.floor(Date.now() / 1000) % account.period) }
    function uri(account) {
        const label = encodeURIComponent(`${account.issuer}:${account.account}`)
        return `otpauth://totp/${label}?secret=${account.secret}&issuer=${encodeURIComponent(account.issuer)}&algorithm=${account.algorithm}&digits=${account.digits}&period=${account.period}`
    }
    function add(account) {
        addMany([account])
    }
    function validAccount(account) {
        if (!account || typeof account !== "object") return false
        const secret = String(account.secret || "").replace(/\s/g, "").toUpperCase()
        const digits = Number(account.digits || 6)
        const period = Number(account.period || 30)
        return String(account.account || "").trim().length > 0 &&
            secret.length <= 512 && /^[A-Z2-7]+$/.test(secret) && ![1, 3, 6].includes(secret.length % 8) &&
            [6, 8].includes(digits) && Number.isFinite(period) && period > 0 && period <= 3600 &&
            ["SHA1", "SHA256", "SHA512"].includes(String(account.algorithm || "SHA1").toUpperCase())
    }
    function addMany(newAccounts) {
        if (!Array.isArray(newAccounts)) return
        let changed = false
        newAccounts.forEach(account => {
            if (!validAccount(account)) return
            const duplicate = accounts.findIndex(item => key(item) === key(account))
            if (duplicate >= 0) accounts[duplicate] = account
            else accounts.push(account)
            changed = true
        })
        if (!changed) return
        root.accounts = accounts.slice()
        save()
        refreshCodes()
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
        if (!accounts.length) { root.codes = ({}); root.codePending = false; return }
        if (codeProcess.running) { root.codePending = true; return }
        root.codePending = false
        root.codeRunningRevision = root.codeRevision
        root.codePayload = root.accounts.slice()
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

    Component.onCompleted: loadProcess.running = true

    Process {
        id: loadProcess
        command: ["secret-tool", "lookup", "application", "illogical-impulse-authenticator"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.accounts = JSON.parse(text || "[]") } catch (error) { root.accounts = [] }
                root.loaded = true
                root.refreshCodes()
            }
        }
        onExited: root.loaded = true
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
            }
        }
        onExited: {
            if (root.codePending) {
                root.codePending = false
                root.refreshCodes()
            }
        }
        stdout: StdioCollector {
            onStreamFinished: {
                if (root.codeRunningRevision !== root.codeRevision) return
                try { root.codes = JSON.parse(text || "{}") } catch (error) { root.codes = ({}) }
            }
        }
    }
    Timer {
        interval: 1000
        running: root.loaded
        repeat: true
        onTriggered: { root.tick += 1; root.refreshCodes() }
    }
}
