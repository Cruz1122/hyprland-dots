import qs
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick.Dialogs

Scope {
    id: root

    property real revealProgress: 0
    property bool panelActive: false
    property bool forcingClose: false
    property bool gestureActive: false
    property real gestureStartProgress: 0
    property bool qrCaptureActive: false
    property bool qrCaptureSelectorSeen: false
    property bool qrCaptureRequestSent: false
    property bool qrCaptureRequestAwaiting: false
    property int qrCaptureBaseRevision: 0
    property real qrCaptureStartedAt: 0
    property string qrCaptureReturnScreen: ""
    property bool dialogVisible: false
    property bool dialogConfirm: false
    property bool dialogDanger: false
    property string dialogTitle: ""
    property string dialogMessage: ""
    property string dialogIcon: "info"
    property string dialogMode: "message"
    property string dialogConfirmText: "Entendido"
    property bool dialogBusy: false
    property int pendingDeleteIndex: -1
    property bool imageQrMigrationOnly: false
    property string imageQrPath: ""
    property bool imageQrBusy: false
    property bool imageQrAwaiting: false
    property bool imageQrTimedOut: false
    property string backupPath: ""
    property string backupPackage: ""
    property string backupPassword: ""
    property bool backupReadBusy: false
    property bool backupReadAwaiting: false
    property bool backupImportBusy: false
    property bool backupImportAwaiting: false
    property string pendingFilePicker: ""
    property string filePickerReturnScreen: ""
    readonly property var selectedScreen: Quickshell.screens.find(screen => screen.name === GlobalStates.authenticatorScreenName) ?? null

    Binding {
        target: GlobalStates
        property: "authenticatorPresented"
        value: root.panelActive
    }

    function closeImmediately(): void {
        root.forcingClose = true;
        root.gestureActive = false;
        root.pendingFilePicker = "";
        root.filePickerReturnScreen = "";
        revealAnimation.stop();
        GlobalStates.authenticatorOpen = false;
        root.panelActive = false;
        root.revealProgress = 0;
        GlobalStates.authenticatorScreenName = "";
        root.forcingClose = false;
    }

    function synchronize(): void {
        if (root.forcingClose) return;
        root.gestureActive = false;
        if (GlobalStates.authenticatorOpen) {
            // Reopening during the exit animation cancels a queued native picker.
            root.pendingFilePicker = "";
            root.filePickerReturnScreen = "";
            // Also support callers that set the existing public flag directly.
            if (!GlobalStates.authenticatorScreenName) GlobalStates.openAuthenticator("");
            if (GlobalStates.screenLocked || !root.selectedScreen) {
                root.closeImmediately();
                return;
            }
            root.panelActive = true;
        } else if (!root.panelActive) {
            return;
        }

        revealAnimation.stop();
        revealAnimation.from = root.revealProgress;
        revealAnimation.to = GlobalStates.authenticatorOpen ? 1 : 0;
        const motion = GlobalStates.authenticatorOpen ? Appearance.animation.elementMoveEnter : Appearance.animation.elementMoveExit;
        // Full-screen travel needs a softer start/finish than a small popup.
        // Keep short reversals long enough to render instead of snapping shut.
        const fullDuration = Math.max(GlobalStates.authenticatorOpen ? 520 : 420, motion.duration);
        revealAnimation.duration = Math.max(160, fullDuration * Math.abs(revealAnimation.to - root.revealProgress));
        revealAnimation.easing.type = Easing.InOutCubic;
        revealAnimation.start();
    }

    function beginDrag(): void {
        if (!root.panelActive || !GlobalStates.authenticatorOpen || root.forcingClose) return;
        revealAnimation.stop();
        root.gestureStartProgress = root.revealProgress;
        root.gestureActive = true;
    }

    function moveDrag(distance: real): void {
        if (!root.gestureActive) return;
        const travel = Math.max(1, root.selectedScreen.height - Appearance.sizes.barHeight);
        root.revealProgress = Math.max(0, root.gestureStartProgress - distance / travel);
    }

    function finishDrag(dismiss: bool): void {
        if (!root.gestureActive) return;
        root.gestureActive = false;
        if (dismiss) GlobalStates.authenticatorOpen = false;
        else root.synchronize();
    }

    function selectMethod(method: string): void {
        if (method === "capture-screen-qr") root.startQrCapture();
        else if (method === "open-qr-image") root.openQrImagePicker(false);
        else if (method === "manual-secret") root.openManualForm();
        else if (method === "paste-otp-uri") root.pasteOtpUri();
        else if (method === "google-migration") root.openQrImagePicker(true);
        else if (method === "encrypted-backup") root.openBackupPicker();
    }

    function storeReady(): bool {
        if (AuthenticatorStore.loaded && !AuthenticatorStore.loadError) return true;
        root.showDialog("Almacén seguro no disponible",
            AuthenticatorStore.loadError
                ? "No se pueden añadir cuentas mientras el almacén seguro esté inaccesible."
                : "Espera a que termine la carga del almacén seguro.",
            "lock", true, false);
        return false;
    }

    function showDialog(title: string, message: string, icon: string, danger: bool, confirm: bool): void {
        root.showDialogMode(title, message, icon, danger, confirm, "message",
            confirm ? "Confirmar" : "Entendido", false);
    }

    function showDialogMode(title: string, message: string, icon: string, danger: bool,
                            confirm: bool, mode: string, confirmText: string, busy: bool): void {
        root.dialogTitle = title;
        root.dialogMessage = message;
        root.dialogIcon = icon;
        root.dialogDanger = danger;
        root.dialogConfirm = confirm;
        root.dialogConfirmText = confirmText;
        root.dialogMode = mode;
        root.dialogBusy = busy;
        root.dialogVisible = true;
    }

    function dismissDialog(): void {
        imageQrTimeout.stop();
        backupReadTimeout.stop();
        backupImportTimeout.stop();
        qrImageDialog.close();
        backupDialog.close();
        imageQrProcess.running = false;
        backupReadProcess.running = false;
        backupImportProcess.running = false;
        root.imageQrBusy = false;
        root.imageQrAwaiting = false;
        root.imageQrPath = "";
        root.backupReadBusy = false;
        root.backupReadAwaiting = false;
        root.backupImportBusy = false;
        root.backupImportAwaiting = false;
        root.backupPath = "";
        root.backupPackage = "";
        root.backupPassword = "";
        root.dialogVisible = false;
        root.dialogConfirm = false;
        root.dialogDanger = false;
        root.dialogBusy = false;
        root.dialogMode = "message";
        root.dialogConfirmText = "Entendido";
        root.pendingDeleteIndex = -1;
    }

    function acceptDialog(formData: var): void {
        if (!root.dialogVisible) return;
        if (root.dialogMode === "delete" && root.pendingDeleteIndex >= 0) {
            AuthenticatorStore.remove(root.pendingDeleteIndex);
            root.pendingDeleteIndex = -1;
            root.showDialog("Código eliminado", "El código se eliminó del almacén seguro.", "delete", false, false);
            return;
        }
        if (root.dialogMode === "manual") {
            if (!AuthenticatorStore.validAccount(formData)) {
                root.dialogMessage = "Revisa la cuenta, la clave Base32 y los parámetros del código.";
                root.dialogIcon = "error";
                root.dialogDanger = true;
                return;
            }
            if (AuthenticatorStore.addMany([formData]) > 0)
                root.showDialog("Código añadido", "El código de autenticación se guardó correctamente.", "check_circle", false, false);
            else {
                root.dialogTitle = "No se pudo añadir";
                root.dialogMessage = "No se encontró una cuenta TOTP válida.";
                root.dialogIcon = "error";
                root.dialogDanger = true;
                root.dialogMode = "message";
                root.dialogConfirm = false;
                root.dialogConfirmText = "Entendido";
            }
            return;
        }
        if (root.dialogMode === "backup-password") {
            const password = String(formData?.password || "");
            if (!password || password.length > 4096) {
                root.dialogMessage = "Introduce una contraseña válida para la copia.";
                root.dialogIcon = "error";
                root.dialogDanger = true;
                return;
            }
            root.backupPassword = password;
            root.beginBackupImport();
            return;
        }
        root.dismissDialog();
    }

    function confirmDeleteAccount(index: int, label: string): void {
        const boundedLabel = label.length > 96 ? label.slice(0, 93) + "…" : label;
        root.pendingDeleteIndex = index;
        root.showDialogMode("¿Borrar código?", `Se eliminará ${boundedLabel} del almacén seguro. Esta acción no se puede deshacer.`,
            "delete", true, true, "delete", "Borrar", false);
    }

    function openManualForm(): void {
        if (!root.storeReady()) return;
        root.showDialogMode("Añadir clave manualmente", "Introduce la cuenta y la clave secreta Base32.",
            "key", false, true, "manual", "Añadir", false);
    }

    function pasteOtpUri(): void {
        if (!root.storeReady()) return;
        const uri = String(Quickshell.clipboardText || "").trim();
        if (!uri || uri.length > 4096) {
            root.showDialog("URI no válida", "El portapapeles no contiene una URI TOTP válida.", "link_off", true, false);
            return;
        }
        const account = AuthenticatorStore.parseUri(uri);
        if (!account) {
            root.showDialog("URI no válida", "El portapapeles no contiene una URI TOTP válida.", "link_off", true, false);
            return;
        }
        const added = AuthenticatorStore.add(account);
        root.showDialog(added > 0 ? "Código añadido" : "No se pudo añadir",
            added > 0 ? "El código de autenticación se guardó correctamente." : "No se encontró una cuenta TOTP válida.",
            added > 0 ? "check_circle" : "error", added <= 0, false);
    }

    function openQrImagePicker(migrationOnly: bool): void {
        if (!root.storeReady()) return;
        root.imageQrMigrationOnly = migrationOnly;
        root.openFilePicker("qr-image");
    }

    function openFilePicker(kind: string): void {
        root.pendingFilePicker = kind;
        root.filePickerReturnScreen = GlobalStates.authenticatorScreenName || root.selectedScreen?.name || "";
        if (root.panelActive) GlobalStates.authenticatorOpen = false;
        else Qt.callLater(() => root.openPendingFilePicker());
    }

    function openPendingFilePicker(): void {
        const kind = root.pendingFilePicker;
        root.pendingFilePicker = "";
        if (!kind || GlobalStates.screenLocked || root.panelActive || GlobalStates.authenticatorOpen) {
            root.filePickerReturnScreen = "";
            return;
        }
        if (kind === "qr-image") {
            qrImageDialog.title = root.imageQrMigrationOnly
                ? "Seleccionar copia QR de Google Authenticator" : "Seleccionar imagen con un código QR";
            qrImageDialog.open();
        } else if (kind === "backup") {
            backupDialog.open();
        }
    }

    function restoreAuthenticatorAfterPicker(): void {
        const screenName = root.filePickerReturnScreen;
        root.filePickerReturnScreen = "";
        if (!GlobalStates.screenLocked) GlobalStates.openAuthenticator(screenName);
    }

    function readQrImage(path: string): void {
        if (!path || !path.startsWith("/")) {
            root.showDialog("No se pudo abrir la imagen", "Selecciona un archivo de imagen local.", "image_not_supported", true, false);
            return;
        }
        root.imageQrPath = path;
        root.imageQrBusy = true;
        root.imageQrAwaiting = false;
        root.showDialogMode("Leyendo imagen QR", "Buscando un código de autenticación en la imagen.",
            "hourglass_empty", false, true, "busy", "Cancelar", true);
        root.imageQrAwaiting = true;
        imageQrProcess.running = true;
        imageQrTimeout.restart();
    }

    function finishImageQr(status: string, payload: string): void {
        if (!root.imageQrBusy) return;
        const migrationOnly = root.imageQrMigrationOnly;
        root.imageQrBusy = false;
        root.imageQrAwaiting = false;
        root.imageQrTimedOut = false;
        imageQrTimeout.stop();
        root.imageQrPath = "";
        root.presentQrResult(status, payload, migrationOnly);
    }

    function openBackupPicker(): void {
        if (!root.storeReady()) return;
        root.openFilePicker("backup");
    }

    function readBackupFile(path: string): void {
        if (!path || !path.startsWith("/")) {
            root.showDialog("Copia no válida", "Selecciona un archivo local de copia cifrada.", "folder_off", true, false);
            return;
        }
        root.backupPath = path;
        root.backupReadBusy = true;
        root.backupReadAwaiting = false;
        root.showDialogMode("Leyendo copia cifrada", "Validando el archivo local.",
            "hourglass_empty", false, true, "busy", "Cancelar", true);
        root.backupReadAwaiting = true;
        backupReadProcess.running = true;
        backupReadTimeout.restart();
    }

    function finishBackupRead(exitCode: int, packageText: string): void {
        if (!root.backupReadBusy) return;
        root.backupReadBusy = false;
        root.backupReadAwaiting = false;
        root.backupPath = "";
        try {
            if (exitCode !== 0 || packageText.length > 5242880) throw new Error("Invalid backup file");
            const backup = JSON.parse(packageText);
            if (!backup || backup.format !== "ii-authenticator-v1") throw new Error("Invalid backup format");
            root.backupPackage = packageText;
            root.showDialogMode("Importar copia cifrada", "Introduce la contraseña usada para cifrar esta copia.",
                "lock", false, true, "backup-password", "Importar", false);
        } catch (error) {
            root.backupPackage = "";
            root.showDialog("No se pudo abrir la copia", "El archivo no es una copia cifrada válida.", "error", true, false);
        }
    }

    function beginBackupImport(): void {
        if (!root.backupPackage || root.backupImportBusy) {
            root.showDialog("Copia no válida", "Selecciona una copia cifrada válida antes de importarla.", "error", true, false);
            return;
        }
        root.backupImportBusy = true;
        root.backupImportAwaiting = false;
        root.showDialogMode("Importando copia", "Validando la contraseña y los códigos cifrados.",
            "hourglass_empty", false, true, "busy", "Cancelar", true);
        root.backupImportAwaiting = true;
        backupImportProcess.stdinEnabled = true;
        backupImportProcess.running = true;
        backupImportTimeout.restart();
    }

    function finishBackupImport(exitCode: int, payload: string): void {
        if (!root.backupImportBusy) return;
        root.backupImportBusy = false;
        root.backupImportAwaiting = false;
        root.backupPackage = "";
        root.backupPassword = "";
        let title = "No se pudo importar la copia";
        let message = "La contraseña es incorrecta o la copia está dañada.";
        let icon = "error";
        let danger = true;
        if (exitCode === 0) {
            try {
                const accounts = JSON.parse(payload || "[]");
                if (!Array.isArray(accounts) || accounts.length === 0 || accounts.some(account => !AuthenticatorStore.validAccount(account)))
                    throw new Error("Invalid imported accounts");
                const added = AuthenticatorStore.addMany(accounts);
                if (added > 0) {
                    title = "Copia importada";
                    message = added === 1 ? "Se añadió 1 código de autenticación." : `Se añadieron ${added} códigos de autenticación.`;
                    icon = "check_circle";
                    danger = false;
                }
            } catch (error) {
                message = "La copia no contiene una lista válida de códigos TOTP.";
            }
        }
        root.showDialog(title, message, icon, danger, false);
    }

    function startQrCapture(): void {
        if (root.qrCaptureActive) return;
        if (!root.storeReady()) return;
        root.qrCaptureActive = true;
        root.qrCaptureSelectorSeen = false;
        root.qrCaptureRequestSent = false;
        root.qrCaptureRequestAwaiting = false;
        root.qrCaptureBaseRevision = GlobalStates.authenticatorQrCaptureRevision;
        root.qrCaptureStartedAt = Date.now();
        root.qrCaptureReturnScreen = GlobalStates.authenticatorScreenName || root.selectedScreen?.name || "";
        root.dismissDialog();
        GlobalStates.authenticatorQrPayload = "";
        GlobalStates.authenticatorQrStatus = "";
        GlobalStates.authenticatorQrScreenName = root.qrCaptureReturnScreen;
        GlobalStates.authenticatorOpen = false;
        qrCaptureWatchdog.restart();
    }

    function presentQrResult(status: string, payload: string, migrationOnly: bool): void {
        let dialogTitle = "Captura cancelada";
        let dialogMessage = "No se añadió ningún código.";
        let dialogIcon = "cancel";
        let dialogDanger = false;
        const lines = String(payload || "").trim().split(/\r?\n/).filter(line => line.trim().length > 0);
        if (status === "decoded" && lines.length > 0) {
            try {
                const accounts = [];
                let sawMigration = false;
                for (const value of lines) {
                    if (value.trim().startsWith("[")) {
                        const migrated = JSON.parse(value);
                        if (!Array.isArray(migrated) || migrated.length === 0) throw new Error("Invalid migration QR");
                        sawMigration = true;
                        accounts.push(...migrated);
                    } else {
                        if (migrationOnly) throw new Error("Not a migration QR");
                        const account = AuthenticatorStore.parseUri(value);
                        if (!account) throw new Error("Unsupported QR payload");
                        accounts.push(account);
                    }
                }
                if (migrationOnly && !sawMigration) throw new Error("Not a migration QR");
                const added = AuthenticatorStore.addMany(accounts);
                if (added > 0) {
                    dialogTitle = added === 1 ? "Código añadido" : "Códigos añadidos";
                    dialogMessage = added === 1 ? "El código de autenticación se guardó correctamente."
                        : `Se guardaron ${added} códigos de autenticación.`;
                    dialogIcon = "check_circle";
                } else {
                    dialogTitle = "QR no válido";
                    dialogMessage = "El QR no contenía cuentas TOTP válidas.";
                    dialogIcon = "qr_code_2";
                    dialogDanger = true;
                }
            } catch (error) {
                dialogTitle = migrationOnly ? "Migración no válida" : "QR no válido";
                dialogMessage = migrationOnly
                    ? "La imagen no contiene una copia QR válida de Google Authenticator."
                    : "El QR no contiene una cuenta TOTP válida.";
                dialogIcon = migrationOnly ? "move_to_inbox" : "qr_code_2";
                dialogDanger = true;
            }
        } else if (status === "not-found") {
            dialogTitle = "No se encontró el QR";
            dialogMessage = "No se detectó un código QR en la región seleccionada.";
            dialogIcon = "qr_code_scanner";
            dialogDanger = true;
        } else if (status === "error") {
            dialogTitle = "Error al leer el QR";
            dialogMessage = "No se pudo leer el código QR. Inténtalo de nuevo.";
            dialogIcon = "error";
            dialogDanger = true;
        }
        root.showDialog(dialogTitle, dialogMessage, dialogIcon, dialogDanger, false);
    }

    function finishQrCapture(): void {
        if (!root.qrCaptureActive || !root.qrCaptureSelectorSeen || GlobalStates.regionSelectorOpen) return;
        qrCaptureWatchdog.stop();
        Quickshell.screens.forEach(screen => Quickshell.execDetached([
            "rm", "-f", "--", `${Directories.screenshotTemp}/image-${screen.name}`
        ]));
        const revision = GlobalStates.authenticatorQrCaptureRevision;
        const status = revision > root.qrCaptureBaseRevision ? GlobalStates.authenticatorQrStatus : "cancelled";
        const payload = revision > root.qrCaptureBaseRevision ? String(GlobalStates.authenticatorQrPayload || "") : "";
        GlobalStates.authenticatorQrPayload = "";
        GlobalStates.authenticatorQrStatus = "";
        GlobalStates.authenticatorQrScreenName = "";
        root.qrCaptureActive = false;
        root.qrCaptureSelectorSeen = false;
        root.qrCaptureRequestSent = false;
        root.qrCaptureRequestAwaiting = false;
        root.presentQrResult(status, payload, false);
        GlobalStates.openAuthenticator(root.qrCaptureReturnScreen);
    }

    function abortQrCapture(notice: string): void {
        if (!root.qrCaptureActive) return;
        qrCaptureWatchdog.stop();
        Quickshell.screens.forEach(screen => Quickshell.execDetached([
            "rm", "-f", "--", `${Directories.screenshotTemp}/image-${screen.name}`
        ]));
        root.qrCaptureActive = false;
        root.qrCaptureSelectorSeen = false;
        root.qrCaptureRequestSent = false;
        root.qrCaptureRequestAwaiting = false;
        GlobalStates.authenticatorQrPayload = "";
        GlobalStates.authenticatorQrStatus = "";
        GlobalStates.authenticatorQrScreenName = "";
        GlobalStates.regionSelectorOpen = false;
        root.showDialog("Captura QR interrumpida", notice, "error", true, false);
        GlobalStates.openAuthenticator(root.qrCaptureReturnScreen);
    }

    onSelectedScreenChanged: {
        if (root.panelActive && !root.selectedScreen) root.closeImmediately();
    }
    Component.onCompleted: root.synchronize()

    Connections {
        target: GlobalStates
        function onAuthenticatorOpenChanged() {
            if (!GlobalStates.authenticatorOpen) root.dismissDialog();
            root.synchronize();
        }
        function onRegionSelectorOpenChanged() {
            if (!root.qrCaptureActive) return;
            if (GlobalStates.regionSelectorOpen) root.qrCaptureSelectorSeen = true;
            else root.finishQrCapture();
        }
        function onScreenLockedChanged() {
            if (!GlobalStates.screenLocked) return;
            root.dismissDialog();
            root.pendingFilePicker = "";
            root.filePickerReturnScreen = "";
            qrImageDialog.close();
            backupDialog.close();
            if (root.qrCaptureActive) root.abortQrCapture("Captura cancelada al bloquear la sesión.");
            else root.closeImmediately();
        }
    }

    NumberAnimation {
        id: revealAnimation
        target: root
        property: "revealProgress"
        alwaysRunToEnd: false
        onFinished: {
            if (!GlobalStates.authenticatorOpen) {
                root.panelActive = false;
                GlobalStates.authenticatorScreenName = "";
                if (root.pendingFilePicker.length > 0)
                    Qt.callLater(() => root.openPendingFilePicker());
            }
        }
    }

    Loader {
        active: root.panelActive
        sourceComponent: PanelWindow {
            id: panel
            screen: root.selectedScreen
            visible: true
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "quickshell:authenticator"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            anchors { top: true; bottom: true; left: true; right: true }

            AuthenticatorCurtain {
                anchors.fill: parent
                store: AuthenticatorStore
                revealProgress: root.revealProgress
                onCloseRequested: GlobalStates.authenticatorOpen = false
                onCodeCopyRequested: code => {
                    if (/^(?:[0-9]{6}|[0-9]{8})$/.test(code)) Quickshell.clipboardText = code;
                }
                dialogVisible: root.dialogVisible
                dialogConfirm: root.dialogConfirm
                dialogDanger: root.dialogDanger
                dialogMode: root.dialogMode
                dialogConfirmText: root.dialogConfirmText
                dialogBusy: root.dialogBusy
                dialogTitle: root.dialogTitle
                dialogMessage: root.dialogMessage
                dialogIcon: root.dialogIcon
                onMethodSelected: method => root.selectMethod(method)
                onDeleteRequested: (index, label) => root.confirmDeleteAccount(index, label)
                onDialogAccepted: formData => root.acceptDialog(formData)
                onDialogDismissed: root.dismissDialog()
                onDragStarted: root.beginDrag()
                onDragMoved: distance => root.moveDrag(distance)
                onDragFinished: dismiss => root.finishDrag(dismiss)
                Component.onCompleted: AuthenticatorStore.viewing = true
                Component.onDestruction: AuthenticatorStore.viewing = false
            }
        }
    }

    IpcHandler {
        target: "authenticator"
        function toggle(): void { GlobalStates.toggleAuthenticator(); }
        function close(): void { GlobalStates.authenticatorOpen = false; }
    }

    GlobalShortcut {
        name: "authenticatorToggle"
        description: "Toggle authenticator"
        onPressed: GlobalStates.toggleAuthenticator()
    }

    FileDialog {
        id: qrImageDialog
        fileMode: FileDialog.OpenFile
        nameFilters: ["Imágenes QR (*.png *.jpg *.jpeg *.webp *.bmp *.tif *.tiff)", "Todos los archivos (*)"]
        onAccepted: {
            const path = selectedFile.toLocalFile();
            root.restoreAuthenticatorAfterPicker();
            root.readQrImage(path);
        }
        onRejected: root.restoreAuthenticatorAfterPicker()
    }

    FileDialog {
        id: backupDialog
        title: "Seleccionar copia cifrada del autenticador"
        fileMode: FileDialog.OpenFile
        nameFilters: ["Copias del autenticador (*.ii-auth *.json)", "Todos los archivos (*)"]
        onAccepted: {
            const path = selectedFile.toLocalFile();
            root.restoreAuthenticatorAfterPicker();
            root.readBackupFile(path);
        }
        onRejected: root.restoreAuthenticatorAfterPicker()
    }

    Process {
        id: imageQrProcess
        command: ["/usr/bin/bash", Quickshell.shellPath("scripts/authenticator-open-image-qr.sh"),
            root.imageQrPath, AuthenticatorStore.python, AuthenticatorStore.script]
        stdout: StdioCollector { id: imageQrOutput }
        stderr: StdioCollector {}
        onRunningChanged: {
            if (running) return;
            Qt.callLater(() => {
                if (root.imageQrBusy && root.imageQrAwaiting && !imageQrProcess.running)
                    root.finishImageQr("error", "");
            });
        }
        onExited: (exitCode, exitStatus) => {
            const payload = String(imageQrOutput.text || "").trim();
            const status = exitCode === 0 && payload.length > 0 ? "decoded"
                : exitCode === 1 ? "not-found" : "error";
            root.finishImageQr(status, payload);
        }
    }

    Timer {
        id: imageQrTimeout
        interval: 50000
        onTriggered: {
            if (!root.imageQrBusy) return;
            imageQrProcess.running = false;
            root.finishImageQr("error", "");
        }
    }

    Process {
        id: backupReadProcess
        command: ["/usr/bin/bash", Quickshell.shellPath("scripts/authenticator-read-backup.sh"), root.backupPath]
        stdout: StdioCollector { id: backupReadOutput }
        stderr: StdioCollector {}
        onRunningChanged: {
            if (running) return;
            Qt.callLater(() => {
                if (root.backupReadBusy && root.backupReadAwaiting && !backupReadProcess.running)
                    root.finishBackupRead(2, "");
            });
        }
        onExited: (exitCode, exitStatus) => root.finishBackupRead(exitCode, String(backupReadOutput.text || ""))
    }

    Timer {
        id: backupReadTimeout
        interval: 6000
        onTriggered: {
            if (!root.backupReadBusy) return;
            backupReadProcess.running = false;
            root.finishBackupRead(2, "");
        }
    }

    Process {
        id: backupImportProcess
        command: ["/usr/bin/timeout", "20s", AuthenticatorStore.python, AuthenticatorStore.script, "import"]
        stdout: StdioCollector { id: backupImportOutput }
        stderr: StdioCollector {}
        onRunningChanged: {
            if (running) {
                write(JSON.stringify({ package: root.backupPackage, password: root.backupPassword }));
                stdinEnabled = false;
                return;
            }
            Qt.callLater(() => {
                if (root.backupImportBusy && root.backupImportAwaiting && !backupImportProcess.running)
                    root.finishBackupImport(2, "");
            });
        }
        onExited: (exitCode, exitStatus) => root.finishBackupImport(exitCode, String(backupImportOutput.text || ""))
    }

    Timer {
        id: backupImportTimeout
        interval: 25000
        onTriggered: {
            if (!root.backupImportBusy) return;
            backupImportProcess.running = false;
            root.finishBackupImport(124, "");
        }
    }

    Process {
        id: qrCaptureRequest
        command: ["/usr/bin/qs", "-c", "ii", "ipc", "call", "region", "authenticatorQr"]
        onRunningChanged: {
            if (running) return;
            Qt.callLater(() => {
                if (root.qrCaptureRequestAwaiting && root.qrCaptureActive
                    && !root.qrCaptureSelectorSeen && !GlobalStates.regionSelectorOpen) {
                    root.qrCaptureRequestAwaiting = false;
                    root.abortQrCapture("No se pudo abrir el selector de región.");
                }
            });
        }
        onExited: (exitCode, exitStatus) => {
            root.qrCaptureRequestAwaiting = false;
            if (root.qrCaptureActive && GlobalStates.authenticatorQrCaptureRevision > root.qrCaptureBaseRevision) {
                root.qrCaptureSelectorSeen = true;
                root.finishQrCapture();
            } else if (root.qrCaptureActive && exitCode !== 0 && !root.qrCaptureSelectorSeen && !GlobalStates.regionSelectorOpen) {
                root.abortQrCapture("No se pudo abrir el selector de región.");
            }
        }
    }

    Timer {
        id: qrCaptureWatchdog
        interval: 100
        repeat: true
        onTriggered: {
            if (!root.qrCaptureActive) { stop(); return; }
            if (Date.now() - root.qrCaptureStartedAt >= 60000) {
                root.abortQrCapture("La captura QR agotó el tiempo.");
                return;
            }
            if (GlobalStates.regionSelectorOpen) {
                root.qrCaptureSelectorSeen = true;
                return;
            }
            if (root.qrCaptureSelectorSeen) {
                root.finishQrCapture();
                return;
            }
            if (!GlobalStates.authenticatorPresented && !root.qrCaptureRequestSent) {
                root.qrCaptureRequestSent = true;
                root.qrCaptureRequestAwaiting = true;
                qrCaptureRequest.running = true;
            }
        }
    }

}
