pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import "../modules/ii/bar/AiQuotaPresentation.js" as Presentation

Singleton {
    id: root
    property var data: ({ providers: {}, accounts: [], selected: {} })
    property bool available: false
    property var pendingSelections: ({})
    property int requestSerial: 0
    property var operationResult: null
    readonly property bool authorizationActive: !!(operationResult?.pending && (operationResult?.url || operationResult?.browser))
    property bool authorizationUiVisible: false
    property bool externalBrowserSetup: false
    property bool overlayCollapsed: false
    property var managerRequestId: null
    property string requestedProvider: ""
    readonly property string operationError: data.operationError ?? ""

    function snapshot(provider) {
        return data.providers?.[provider] ?? {
            name: provider, status: "unconfigured", windows: [], alias: "", source: "",
            sources: [Presentation.defaultSource(provider)],
            message: available ? "Configura una cuenta en Ajustes → Servicios → Cuotas de IA."
                               : "Servicio de cuotas no disponible.",
            identityVerified: false, observedAt: null
        };
    }

    function accountsFor(provider) {
        return (data.accounts ?? []).filter(account => account.provider === provider);
    }

    function send(command) {
        if (backend.running)
            backend.write(JSON.stringify(command) + "\n");
    }

    // GUI-driven account actions: the credential is typed in a dialog and sent
    // straight to the private backend; no terminal is ever spawned.
    function add(provider, alias, secret, source) {
        const requestId = ++root.requestSerial;
        root.send({ action: "add", provider: provider, alias: alias, secret: secret, source: source, requestId: requestId });
        return requestId;
    }

    function login(provider, alias, source, consent, install) {
        root.externalBrowserSetup = false;
        root.authorizationUiVisible = false;
        root.overlayCollapsed = false;
        const requestId = ++root.requestSerial;
        root.send({ action: install ? "install-login" : "login", provider: provider, alias: alias,
            source: source, consent: consent === true, requestId: requestId });
        return requestId;
    }

    function cancel(requestId) {
        if (requestId !== null) root.send({ action: "cancel", requestId: requestId });
    }

    function showAuthorizationUi() {
        root.externalBrowserSetup = false;
        root.authorizationUiVisible = true;
        root.overlayCollapsed = false;
    }

    function collapseOverlay() {
        root.overlayCollapsed = true;
    }

    function authorizeCode(requestId, code) {
        root.send({ action: "authorize-code", requestId: requestId, code: code });
    }

    function prepareBrowser() {
        const requestId = ++root.requestSerial;
        root.send({ action: "prepare-browser", requestId: requestId });
        return requestId;
    }

    function continueBrowserSetup(path) {
        if (!path) return;
        Quickshell.execDetached(["wl-copy", path]);
        root.openExtensionManager();
        root.collapseOverlay();
    }

    function openExtensionManager() {
        const requestId = ++root.requestSerial;
        root.managerRequestId = requestId;
        root.externalBrowserSetup = true;
        root.send({ action: "open-browser-manager", requestId: requestId });
    }

    function requestConnection(provider) {
        if (!["codex", "opencode", "antigravity", "cursor", "zed", "claude"].includes(provider)) return;
        if (root.operationResult?.pending) {
            root.showAuthorizationUi();
            return;
        }
        root.requestedProvider = provider;
    }

    function reconnect(accountId, secret) {
        const requestId = ++root.requestSerial;
        root.send({ action: "reconnect", accountId: accountId, secret: secret, requestId: requestId });
        return requestId;
    }

    function remove(accountId) {
        root.send({ action: "remove", accountId: accountId });
    }

    function rename(accountId, alias) {
        root.send({ action: "rename", accountId: accountId, alias: alias });
    }

    function select(provider, accountId) {
        // Clear immediately; backend generation/identity gates reject old replies too.
        const providers = Object.assign({}, data.providers);
        const pending = Object.assign({}, pendingSelections);
        pending[provider] = { accountId: accountId, generation: (providers[provider]?.generation ?? 0) + 1 };
        pendingSelections = pending;
        delete providers[provider];
        root.data = Object.assign({}, data, { providers: providers });
        root.send({ action: "select", accountId: accountId });
    }

    function disable(provider) {
        const accountId = data.selected?.[provider];
        if (accountId) {
            const providers = Object.assign({}, data.providers);
            const pending = Object.assign({}, pendingSelections);
            pending[provider] = { accountId: null, generation: (providers[provider]?.generation ?? 0) + 1 };
            pendingSelections = pending;
            delete providers[provider];
            root.data = Object.assign({}, data, { providers: providers });
            root.send({ action: "disable", accountId: accountId });
        }
    }

    function refresh(provider) {
        root.send({ action: "refresh", provider: provider });
    }

    Process {
        id: backend
        command: ["/usr/bin/python3", "-B", Directories.scriptPath + "/ai-quotas.py", "serve"]
        running: true
        stdinEnabled: true
        stdout: SplitParser {
            onRead: line => {
                try {
                    const next = JSON.parse(line);
                    if (next.version === 1 && next.providers && Array.isArray(next.accounts)) {
                        const pending = Object.assign({}, root.pendingSelections);
                        for (const provider of Object.keys(pending)) {
                            if (Presentation.selectionAcknowledged(pending[provider], next.selected?.[provider], next.providers[provider])) {
                                delete pending[provider];
                            } else {
                                delete next.providers[provider];
                                next.selected[provider] = pending[provider].accountId;
                            }
                        }
                        root.pendingSelections = pending;
                        root.data = next;
                        root.operationResult = next.operationResult ?? null;
                        if (root.operationResult?.requestId === root.managerRequestId && root.operationResult?.ok === false)
                            root.externalBrowserSetup = false;
                        root.available = true;
                    }
                } catch (error) {
                    root.available = false;
                }
            }
        }
        onExited: {
            root.operationResult = null;
            root.authorizationUiVisible = false;
            root.externalBrowserSetup = false;
            root.overlayCollapsed = false;
            root.available = false;
            root.pendingSelections = ({});
            root.data = { providers: {}, accounts: [], selected: {} };
        }
    }
}
