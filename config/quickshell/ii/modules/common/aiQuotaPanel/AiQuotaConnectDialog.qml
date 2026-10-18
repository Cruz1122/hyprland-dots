import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import "../../ii/bar/AiQuotaPresentation.js" as Presentation

// GUI replacement for the old terminal account manager. The credential is typed
// here and handed straight to the private backend over its stdin channel; it is
// never passed as an argument, echoed to a shell, or shown in a terminal.
WindowDialog {
    id: root
    property string provider: ""
    property string providerName: ""
    property string source: ""
    property string accountId: ""
    property bool reconnectMode: false
    property string alias: ""
    property string secret: ""
    property string errorMessage: ""
    property bool submitting: false
    property var pendingRequestId: null
    property string authorizationUrl: ""
    property string progressMessage: ""
    property bool requiresCode: false
    property var setupRequestId: null
    property bool preparingBrowser: false
    property string setupPath: ""

    readonly property bool bridge: root.source === "opencode-bridge"
    readonly property bool browserLinked: root.source === "browser-extension"
    readonly property bool browserSession: root.source === "browser-session" || root.browserLinked
    readonly property bool nativeLogin: root.source === "agy-cli" || root.source === "claude-statusline"
    readonly property bool cli: root.source.endsWith("-cli") || root.bridge || root.browserSession || root.source === "claude-statusline"
    readonly property bool requiresInstall: root.nativeLogin && !!AiQuotaUsage.snapshot(root.provider).requiresInstall
    readonly property bool supported: root.source.length > 0
    readonly property string accountUrl: {
        switch (root.provider) {
        case "opencode": return "https://opencode.ai/console";
        case "cursor": return "https://cursor.com/dashboard";
        case "zed": return "https://zed.dev/sign_in";
        case "claude": return "https://claude.ai/settings/usage";
        case "antigravity": return "https://antigravity.google/";
        default: return "";
        }
    }
    readonly property string secretPlaceholder: {
        switch (root.source) {
        case "api-key": return "API key de OpenCode Go";
        case "cursor-cookie": return "Valor de WorkosCursorSessionToken";
        case "zed-cookie": return "Valor de zed.session";
        case "claude-oauth": return "Token OAuth de Claude Code (no API key)";
        default: return "Credencial";
        }
    }

    signal dismissed()

    anchors.fill: parent
    z: 1000
    visible: root.show
    backgroundWidth: 560
    backgroundHeight: Math.min(root.height - 48, root.browserLinked ? 780 : 580)
    Component.onDestruction: {
        if (root.submitting) AiQuotaUsage.cancel(root.pendingRequestId);
    }
    onDismiss: {
        if (root.submitting) AiQuotaUsage.cancel(root.pendingRequestId);
        root.submitting = false;
        root.dismissed();
    }
    onShowChanged: {
        if (root.show) {
            if (root.source === "browser-session") root.source = "browser-extension";
            root.alias = root.providerName;
            root.secret = "";
            root.errorMessage = "";
            root.submitting = false;
            root.pendingRequestId = null;
            root.authorizationUrl = "";
            root.progressMessage = "";
            root.requiresCode = false;
            root.preparingBrowser = false;
            authorizationCode.text = "";
            internalConsent.checked = false;
            manualSetup.checked = !root.cli;
        } else {
            if (AiQuotaUsage.overlayCollapsed) return;
            if (root.submitting) AiQuotaUsage.cancel(root.pendingRequestId);
            root.submitting = false;
            root.secret = "";
            authorizationCode.text = "";
        }
    }

    Connections {
        target: AiQuotaUsage
        function onOperationResultChanged() {
            const result = AiQuotaUsage.operationResult;
            if (root.preparingBrowser && result?.requestId === root.setupRequestId) {
                root.preparingBrowser = false;
                if (result.ok) {
                    root.setupPath = result.setupPath || "";
                    root.errorMessage = "Listo: copié la carpeta y abrí el gestor de extensiones en tu Brave habitual. Activa Modo desarrollador → Cargar descomprimida. Selecciona la carpeta que se muestra. Luego vuelve con el emblema de IA y pulsa Conectar.";
                    AiQuotaUsage.continueBrowserSetup(root.setupPath);
                }
                else root.errorMessage = result.message || "No se pudo preparar el enlace del navegador.";
                return;
            }
            if (!root.submitting || !result || result.requestId !== root.pendingRequestId) return;
            if (result.pending) {
                root.requiresCode = result.requiresCode === true;
                root.progressMessage = result.message || "Conectando…";
                if (result.url && result.url !== root.authorizationUrl) {
                    if (!Presentation.authorizationUrlAllowed(result.url, root.provider)) {
                        AiQuotaUsage.cancel(root.pendingRequestId);
                        root.submitting = false;
                        root.errorMessage = "URL de autorización no válida.";
                        return;
                    }
                    root.authorizationUrl = result.url;
                    // Validate at both the backend and desktop trust boundaries.
                    Qt.openUrlExternally(result.url);
                }
                return;
            }
            root.submitting = false;
            authorizationCode.text = "";
            if (result.ok) root.dismiss();
            else if (result.code === "browser-link-required" && root.browserLinked) {
                root.errorMessage = "Voy a preparar el enlace para tu Brave habitual. Solo tendrás que activar la extensión local una vez.";
                root.preparingBrowser = true;
                root.setupRequestId = AiQuotaUsage.prepareBrowser();
            } else root.errorMessage = result.message || "No se pudo conectar. Revisa los datos e inténtalo de nuevo.";
        }
    }

    ScrollView {
        id: formScroll
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.minimumHeight: 0
        clip: true
        contentWidth: availableWidth
        contentHeight: form.implicitHeight
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

    ColumnLayout {
        id: form
        width: formScroll.availableWidth
        spacing: 16

    WindowDialogTitle {
        Layout.fillWidth: true
        text: (root.reconnectMode ? "Reconectar · " : "Conectar · ") + root.providerName
    }

    WindowDialogParagraph {
        Layout.fillWidth: true
        text: !root.supported ? "Este proveedor no dispone de conexión automática."
            : root.browserLinked
                ? "Se usará tu Brave habitual y su sesión de Cursor/Zed. Si falta la extensión local, el panel la prepara y te lleva al paso de activarla. No copies códigos, tokens ni cookies."
            : root.browserSession
                ? "Se abrirá una ventana de navegador propia del panel. Inicia sesión una vez y tus límites se actualizarán aquí. No se leen otros perfiles del navegador ni del editor."
            : root.source === "claude-statusline"
                ? "Se activará el enlace de límites en la configuración de Claude Code, sin copiar tokens y conservando tu barra de estado actual. Los datos llegan después de tu primera respuesta con Pro/Max; el panel no envía mensajes."
            : root.source === "agy-cli"
                ? "Inicia sesión con Google mediante el cliente oficial de Antigravity. El panel consultará sus límites de Google AI Pro, no la cuota de Gemini API."
            : root.bridge && root.provider === "codex"
                ? "Usa tu sesión de ChatGPT en OpenCode o inicia sesión en el navegador. El fork consulta los consumos y los muestra aquí, sin necesitar Codex CLI."
            : root.bridge
                ? "Se consulta el consumo de Go con la cuenta configurada en tu fork de OpenCode. No se copian sus credenciales al panel."
            : root.source === "codex-cli"
                ? "Se usa Codex CLI autenticado. La sesión de la app ChatGPT no se importa automáticamente; se requiere el cliente codex instalado."
            : root.cli ? "Se usará la sesión activa del cliente oficial. La barra no cambia ni guarda su inicio de sesión."
            : "La credencial se guarda SOLO en tu llavero. No se leen cookies del navegador automáticamente."
    }

    ComboBox {
        Layout.fillWidth: true
        visible: !root.reconnectMode && root.provider === "opencode"
        model: ["Usar cuenta de OpenCode", "Introducir API key de Go"]
        currentIndex: root.source === "api-key" ? 1 : 0
        onActivated: index => root.source = index === 0 ? "opencode-bridge" : "api-key"
    }

    CheckBox {
        id: manualSetup
        Layout.fillWidth: true
        visible: root.provider === "cursor" || root.provider === "zed" || root.provider === "claude"
        text: "No puedo usar el navegador (cookie manual, avanzada)"
        enabled: !root.submitting
        onToggled: {
            const sources = AiQuotaUsage.snapshot(root.provider).sources ?? [];
            root.source = checked ? (root.provider === "claude" ? "claude-oauth" : root.provider + "-cookie") : (sources[0] ?? "");
        }
    }

    DialogButton {
        visible: root.browserLinked
        enabled: !root.submitting && !root.preparingBrowser
        buttonText: root.preparingBrowser ? "Preparando…" : "Configurar conexión en mi Brave (una vez)"
        onClicked: {
            root.preparingBrowser = true;
            root.setupRequestId = AiQuotaUsage.prepareBrowser();
        }
    }

    MaterialTextField {
        Layout.fillWidth: true
        visible: root.browserLinked && root.setupPath.length > 0
        readOnly: true
        text: root.setupPath
        Accessible.name: "Carpeta de la extensión"
    }

    WindowDialogParagraph {
        Layout.fillWidth: true
        visible: root.browserLinked && root.setupPath.length > 0
        text: "Pasos: 1) En Brave, activa Modo desarrollador. 2) Pulsa Cargar descomprimida y selecciona esta carpeta (ya está copiada). 3) Vuelve a este diálogo con el emblema de IA y pulsa Conectar. No vuelvas a iniciar sesión: se usa tu sesión actual de Brave."
    }

    RowLayout {
        visible: root.browserLinked && root.setupPath.length > 0
        DialogButton {
            buttonText: "Copiar carpeta"
            onClicked: Quickshell.execDetached(["wl-copy", root.setupPath])
        }
        DialogButton {
            buttonText: "Abrir gestor de extensiones"
            onClicked: AiQuotaUsage.openExtensionManager()
        }
    }

    CheckBox {
        id: internalConsent
        Layout.fillWidth: true
        visible: root.browserSession
        enabled: !root.submitting
        text: "Permito leer solo mis límites desde la sesión web de Cursor/Zed"
    }

    WindowDialogParagraph {
        Layout.fillWidth: true
        visible: root.browserSession || !root.cli && (root.provider === "cursor" || root.provider === "zed" || root.provider === "claude")
        text: root.browserSession
            ? "Usa un endpoint interno, no una API pública. Puede dejar de funcionar; el proveedor puede restringir su uso o la cuenta. No se eluden captchas ni bloqueos."
            : root.provider === "claude"
            ? "Consulta de uso OAuth de tu propia sesión de Claude Code. No se generan mensajes ni se renueva el token. Este endpoint es interno y puede rechazar el acceso."
            : "Inicia sesión en la web oficial y proporciona explícitamente el valor de sesión indicado. Se valida contra el endpoint de uso antes de guardarlo; abrir la web no conecta el panel por sí solo."
    }

    WindowDialogParagraph {
        Layout.fillWidth: true
        visible: root.requiresInstall
        text: "Se descargará un cliente oficial verificado por hash en una carpeta privada del panel (Linux x86_64). No requiere sudo ni modifica tu PATH. Al continuar autorizas la instalación y el inicio de sesión."
    }

    DialogButton {
        visible: root.accountUrl.length > 0 && !root.cli
        buttonText: "Abrir la web (no conecta por sí sola)"
        onClicked: Qt.openUrlExternally(root.accountUrl)
    }

    StyledText {
        Layout.fillWidth: true
        visible: root.submitting
        text: root.progressMessage || "Conectando…"
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        font.pixelSize: Appearance.font.pixelSize.small
    }

    MaterialTextField {
        id: authorizationCode
        objectName: "aiQuotaAuthorizationCode"
        Layout.fillWidth: true
        visible: root.submitting && root.requiresCode
        placeholderText: "Código de autorización del navegador"
        echoMode: TextInput.Password
        maximumLength: 2048
        Accessible.name: "Código de autorización"
    }

    DialogButton {
        visible: root.submitting && root.requiresCode
        enabled: authorizationCode.text.trim().length >= 8
        buttonText: "Continuar con el código"
        onClicked: {
            AiQuotaUsage.authorizeCode(root.pendingRequestId, authorizationCode.text);
            authorizationCode.text = "";
            root.requiresCode = false;
        }
    }

    Timer {
        interval: 365000
        running: root.submitting
        onTriggered: {
            AiQuotaUsage.cancel(root.pendingRequestId);
            root.submitting = false;
            root.errorMessage = "La conexión agotó el tiempo de espera. Inténtalo de nuevo.";
        }
    }

    MaterialTextField {
        objectName: "aiQuotaConnectAlias"
        Layout.fillWidth: true
        Layout.preferredHeight: 54
        visible: root.supported && !root.cli && !root.reconnectMode
        placeholderText: "Alias local"
        text: root.alias
        onTextEdited: root.alias = text
        Accessible.name: "Alias local"
    }

    MaterialTextField {
        objectName: "aiQuotaConnectSecret"
        Layout.fillWidth: true
        Layout.preferredHeight: 54
        visible: root.supported && !root.cli
        placeholderText: root.secretPlaceholder
        echoMode: TextInput.Password
        maximumLength: 16384
        text: root.secret
        onTextEdited: root.secret = text
        Accessible.name: root.secretPlaceholder
    }

    StyledText {
        objectName: "aiQuotaConnectError"
        Layout.fillWidth: true
        visible: root.errorMessage.length > 0
        text: root.errorMessage
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        color: Appearance.colors.colError
        font.pixelSize: Appearance.font.pixelSize.small
    }

    WindowDialogButtonRow {
        DialogButton {
            visible: root.submitting || root.preparingBrowser || AiQuotaUsage.externalBrowserSetup
            buttonText: "Plegar overlay y continuar"
            Accessible.name: "Plegar overlay y continuar sin cancelar la conexión"
            onClicked: AiQuotaUsage.collapseOverlay()
        }
        DialogButton {
            visible: root.bridge && root.provider === "codex"
            buttonText: "Iniciar sesión"
            enabled: !root.submitting
            onClicked: {
                root.errorMessage = "";
                root.submitting = true;
                root.pendingRequestId = AiQuotaUsage.login(root.provider, root.alias, root.source, false, false);
            }
        }
        DialogButton {
            objectName: "aiQuotaConnectCancel"
            buttonText: "Cancelar"
            onClicked: root.dismiss()
        }
        DialogButton {
            objectName: "aiQuotaConnectConfirm"
            buttonText: root.submitting ? "Conectando…" : root.requiresInstall ? "Instalar y conectar" : root.reconnectMode ? "Reconectar" : "Conectar"
            colEnabled: Appearance.colors.colPrimary
            enabled: AiQuotaUsage.available && root.supported && !root.submitting && (!root.browserSession || internalConsent.checked)
            onClicked: {
                root.errorMessage = "";
                root.submitting = true;
                if (root.browserSession || root.nativeLogin)
                    root.pendingRequestId = AiQuotaUsage.login(root.provider, root.alias, root.source, internalConsent.checked, root.requiresInstall);
                else if (root.reconnectMode)
                    root.pendingRequestId = AiQuotaUsage.reconnect(root.accountId, root.secret);
                else
                    root.pendingRequestId = AiQuotaUsage.add(root.provider, root.alias, root.secret, root.source);
            }
        }
    }
    }
    }
}
