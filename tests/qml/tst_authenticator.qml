import QtQuick
import QtTest
import "../../config/quickshell/ii/modules/common/authenticator" as Auth
import "../../config/quickshell/ii/modules/common/authenticator/AuthenticatorModel.js" as Model

TestCase {
    id: testCase
    name: "AuthenticatorComponents"
    when: windowShown
    visible: true
    width: 1000
    height: 600
    property var curtain: null
    property bool gestureActive: false
    property real gestureStart: 1

    QtObject {
        id: fakeStore
        property bool loaded: true
        property bool loadError: false
        property bool codeError: false
        property var entries: []
        property var codes: ({})
        property var gate: ({ open: true })
        property var removedIndices: []
        property int retries: 0
        function codeFor(entry) { return gate.open ? codes[entry.key] || "" : ""; }
        function retry() { retries += 1; loadError = false; codeError = false; }
        function remove(index) { removedIndices.push(index); }
    }

    Component { id: curtainFactory; Auth.AuthenticatorCurtain {} }
    SignalSpy { id: closeSpy; signalName: "closeRequested" }
    SignalSpy { id: dragSpy; signalName: "dragFinished" }
    SignalSpy { id: copySpy; signalName: "codeCopyRequested" }
    SignalSpy { id: methodSpy; signalName: "methodSelected" }
    SignalSpy { id: deleteSpy; signalName: "deleteRequested" }
    SignalSpy { id: acceptedSpy; signalName: "dialogAccepted" }
    SignalSpy { id: dismissedSpy; signalName: "dialogDismissed" }

    function init() {
        fakeStore.loaded = true;
        fakeStore.loadError = false;
        fakeStore.codeError = false;
        fakeStore.entries = [];
        fakeStore.codes = ({});
        fakeStore.gate = ({ open: true });
        fakeStore.removedIndices = [];
        fakeStore.retries = 0;
        gestureActive = false;
        curtain = curtainFactory.createObject(testCase, { width: 1000, height: 600,
            revealProgress: 1, store: fakeStore });
        verify(curtain !== null);
        compare(findChild(curtain, "authenticatorFeedbackDialog").visible, false);
        curtain.dragStarted.connect(function() {
            gestureActive = true;
            gestureStart = curtain.revealProgress;
        });
        curtain.dragMoved.connect(function(distance) {
            if (gestureActive) curtain.revealProgress = Math.max(0, gestureStart - distance / 560);
        });
        curtain.dragFinished.connect(function(dismiss) {
            gestureActive = false;
            if (dismiss) curtain.closeRequested();
            else curtain.revealProgress = 1;
        });
        closeSpy.target = curtain;
        dragSpy.target = curtain;
        copySpy.target = curtain;
        methodSpy.target = findChild(curtain, "authenticatorMethodGrid");
        deleteSpy.target = curtain;
        acceptedSpy.target = curtain;
        dismissedSpy.target = curtain;
        closeSpy.clear();
        dragSpy.clear();
        copySpy.clear();
        methodSpy.clear();
        curtain.dialogDismissed.connect(function() { curtain.dialogVisible = false; });
        curtain.dialogAccepted.connect(function() { curtain.dialogVisible = false; });
        deleteSpy.clear();
        acceptedSpy.clear();
        dismissedSpy.clear();
        wait(20);
    }

    function cleanup() {
        closeSpy.target = null;
        dragSpy.target = null;
        copySpy.target = null;
        methodSpy.target = null;
        deleteSpy.target = null;
        acceptedSpy.target = null;
        dismissedSpy.target = null;
        curtain.destroy();
        curtain = null;
        wait(0);
    }

    function entry(issuer, account, period, digits) {
        return { key: issuer + "\u0000" + account, issuer: issuer,
            account: account, period: period || 30, digits: digits || 6 };
    }

    function descendants(item, name) {
        let result = [];
        for (const child of item.children || []) {
            if (child.objectName === name) result.push(child);
            result = result.concat(descendants(child, name));
        }
        return result;
    }

    function test_model_validation_and_secret_free_entries() {
        const value = { issuer: "Example", account: "demo", secret: "JBSWY3DPEHPK3PXP", period: 30, digits: 6 };
        const loaded = Model.loadAccounts(JSON.stringify([value, value]));
        compare(loaded.length, 1);
        const display = Model.displayEntries(loaded);
        verify(!("secret" in display[0]));
        compare(display[0].key, "Example\u0000demo");
        for (const invalid of [null, {}, Object.assign({}, value, { period: 0 }),
            Object.assign({}, value, { period: 1.5 }), Object.assign({}, value, { digits: 7 }),
            Object.assign({}, value, { secret: "invalid!" }), Object.assign({}, value, { account: "" })]) {
            compare(Model.normalizeAccount(invalid), null);
        }
        let failed = false;
        try { Model.loadAccounts("{}"); } catch (error) { failed = true; }
        verify(failed);
    }

    function test_model_rollover_and_formatting() {
        const value = entry("Example", "demo", 30, 6);
        const codes = {}; codes[value.key] = "012345";
        compare(Model.currentCode(value, codes, 29, 29.9), "012345");
        compare(Model.currentCode(value, codes, 29, 30), "");
        compare(Model.currentCode(value, codes, -1, 30), "");
        compare(Model.formattedCode("012345"), "012 345");
        compare(Model.formattedCode("00123456"), "0012 3456");
        compare(Model.remainingFraction(30, 30), 1);
        compare(Model.remainingFraction(30, 15), 0.5);
        compare(Model.remainingFraction(60, 15), 0.75);
        compare(Model.windowSignature([value], 29), "[0]");
        compare(Model.windowSignature([value], 30), "[1]");
    }

    function test_empty_state_centered_and_clock_stopped() {
        const status = findChild(curtain, "authenticatorAccountStatus");
        const panel = findChild(curtain, "authenticatorNavigation");
        verify(status.visible);
        compare(findChild(curtain, "authenticatorEmptyCopy").text, "Aún no tienes códigos guardados.");
        const center = status.mapToItem(panel, status.width / 2, status.height / 2);
        fuzzyCompare(center.x, panel.width / 2, 1);
        fuzzyCompare(center.y, panel.height / 2, 1);
        compare(findChild(curtain, "authenticatorCountdownClock").running, false);
        compare(findChild(curtain, "authenticatorAccountList").visible, false);
        const right = findChild(curtain, "authenticatorContent");
        compare(descendants(right, "authenticatorMethodOption").length, 6);
        fuzzyCompare(panel.width / (panel.width + right.width), 0.2, 0.002);
    }

    function test_right_panel_has_six_centered_authentication_method_options() {
        const grid = findChild(curtain, "authenticatorMethodOptions");
        const options = descendants(curtain, "authenticatorMethodOption");
        compare(grid.columns, 3);
        compare(grid.rows, 2);
        compare(options.length, 6);
        const titles = ["Capturar QR", "Abrir imagen", "Clave manual", "Pegar URI", "Migrar cuentas", "Importar copia"];
        for (let index = 0; index < titles.length; index++) {
            verify(descendants(options[index], "authenticatorMethodTitle").some(item => item.text === titles[index]));
            verify(descendants(options[index], "authenticatorMethodDescription").some(item => item.text.length > 0));
            const icon = descendants(options[index], "authenticatorMethodIcon")[0];
            verify(icon.text.length > 0);
            const title = descendants(options[index], "authenticatorMethodTitle")[0];
            verify(icon.mapToItem(options[index], 0, 0).y < title.mapToItem(options[index], 0, 0).y);
        }
        for (let index = 0; index < options.length; index++) compare(options[index].enabled, true);
        for (let row = 0; row < 2; row++) {
            const current = options.filter(option => option.y === options[row * 3].y);
            compare(current.length, 3);
            const ordered = [...current].sort((left, right) => left.x - right.x);
            for (const option of ordered) {
                fuzzyCompare(option.width, ordered[0].width, 1);
                fuzzyCompare(option.height, options[0].height, 1);
            }
        }
        verify(options[3].y > options[0].y);
    }

    function test_each_method_option_dispatches_its_method_id() {
        const options = descendants(curtain, "authenticatorMethodOption");
        const ids = ["capture-screen-qr", "open-qr-image", "manual-secret", "paste-otp-uri", "google-migration", "encrypted-backup"];
        for (let index = 0; index < options.length; index++) {
            mouseClick(options[index], options[index].width / 2, options[index].height / 2);
            compare(methodSpy.signalArguments[index][0], ids[index]);
        }
        compare(methodSpy.count, ids.length);
    }

    function test_loading_and_error_are_not_empty() {
        fakeStore.loaded = false;
        wait(0);
        compare(findChild(curtain, "authenticatorEmptyCopy").text, "Cargando tus códigos…");
        compare(descendants(curtain, "authenticatorMethodOption")[0].enabled, false);
        fakeStore.loaded = true;
        fakeStore.loadError = true;
        wait(0);
        compare(findChild(curtain, "authenticatorEmptyCopy").text, "No se pudieron cargar los códigos.");
        compare(descendants(curtain, "authenticatorMethodOption")[0].enabled, false);
        compare(findChild(curtain, "authenticatorCountdownClock").running, false);
    }

    function test_list_codes_caption_and_ring() {
        const value = entry("Example", "demo", 30, 6);
        fakeStore.codes = { "Example\u0000demo": "012345" };
        fakeStore.entries = [value];
        const list = findChild(curtain, "authenticatorAccountList");
        tryCompare(list, "count", 1);
        wait(30);
        verify(list.visible);
        const code = findChild(list, "authenticatorCode");
        const caption = findChild(list, "authenticatorAccountCaption");
        verify(code !== null && caption !== null);
        compare(code.text, "012 345");
        compare(caption.text, "Example · demo");
        verify(code.mapToItem(list, 0, 0).y < caption.mapToItem(list, 0, 0).y);
        const ring = findChild(list, "authenticatorCountdown");
        verify(ring.remaining > 0 && ring.remaining <= 1);
        compare(findChild(curtain, "authenticatorCountdownClock").running, true);
    }

    function test_many_accounts_scroll() {
        const values = [];
        for (let index = 0; index < 30; index++) values.push(entry("Example", "demo" + index));
        fakeStore.entries = values;
        const list = findChild(curtain, "authenticatorAccountList");
        tryCompare(list, "count", 30);
        wait(30);
        verify(list.contentHeight > list.height);
        list.positionViewAtEnd();
        verify(list.contentY > 0);
    }

    function test_handle_click_and_escape() {
        const handle = findChild(curtain, "authenticatorCloseHandle");
        mouseClick(handle, handle.width / 2, handle.height / 2);
        compare(closeSpy.count, 1);
        handle.forceActiveFocus();
        keyClick(Qt.Key_Escape);
        compare(closeSpy.count, 2);
    }

    function test_click_copies_raw_code_and_feedback_keeps_geometry() {
        fakeStore.codes = { "Example\u0000demo": "00123456" };
        fakeStore.entries = [entry("Example", "demo", 30, 8)];
        const list = findChild(curtain, "authenticatorAccountList");
        tryCompare(list, "count", 1);
        wait(30);
        const button = findChild(list, "authenticatorAccountButton");
        const originalHeight = button.height;
        mouseMove(button, button.width / 2, button.height / 2);
        tryCompare(button, "hovered", true);
        mouseClick(button, button.width / 2, button.height / 2);
        compare(copySpy.count, 1);
        compare(copySpy.signalArguments[0][0], "00123456");
        compare(button.copied, true);
        const feedback = findChild(button, "authenticatorCopyFeedback");
        compare(feedback.text, "Copiado");
        wait(160);
        compare(feedback.opacity, 1);
        fuzzyCompare(button.height, originalHeight, 0.1);
        const timeout = findChild(button, "authenticatorCopyTimeout");
        compare(timeout.interval, 1200);
        timeout.interval = 40;
        timeout.restart();
        tryCompare(button, "copied", false);
        fuzzyCompare(button.height, originalHeight, 0.1);
    }

    function test_expired_code_at_activation_is_not_copied() {
        fakeStore.codes = { "Example\u0000demo": "012345" };
        fakeStore.entries = [entry("Example", "demo")];
        const list = findChild(curtain, "authenticatorAccountList");
        tryCompare(list, "count", 1);
        wait(30);
        const button = findChild(list, "authenticatorAccountButton");
        verify(button.enabled);
        mousePress(button, button.width / 2, button.height / 2);
        // Mutable fake gate mimics rollover after render/press without a model change.
        fakeStore.gate.open = false;
        mouseRelease(button, button.width / 2, button.height / 2);
        compare(copySpy.count, 0);
        compare(button.copied, false);
    }

    function test_keyboard_copies_and_escape_still_closes() {
        fakeStore.codes = { "Example\u0000demo": "012345" };
        fakeStore.entries = [entry("Example", "demo")];
        const list = findChild(curtain, "authenticatorAccountList");
        tryCompare(list, "count", 1);
        wait(30);
        const button = findChild(list, "authenticatorAccountButton");
        button.forceActiveFocus();
        keyClick(Qt.Key_Space);
        compare(copySpy.count, 1);
        compare(copySpy.signalArguments[0][0], "012345");
        keyClick(Qt.Key_Escape);
        compare(closeSpy.count, 1);
    }

    function test_right_click_account_requests_delete_without_copy() {
        fakeStore.codes = { "Example\u0000demo": "012345" };
        fakeStore.entries = [entry("Example", "demo")];
        const list = findChild(curtain, "authenticatorAccountList");
        tryCompare(list, "count", 1);
        wait(30);
        const row = findChild(list, "authenticatorAccountButton");
        mouseClick(row, row.width / 2, row.height / 2, Qt.RightButton);
        compare(deleteSpy.count, 1);
        compare(deleteSpy.signalArguments[0][0], 0);
        compare(deleteSpy.signalArguments[0][1], "Example · demo");
        compare(copySpy.count, 0);
    }

    function test_qr_feedback_is_a_centered_icon_message_modal() {
        curtain.dialogTitle = "Error al leer el QR";
        curtain.dialogMessage = "No se pudo leer el código QR.";
        curtain.dialogIcon = "error";
        curtain.dialogVisible = true;
        wait(30);
        const dialog = findChild(curtain, "authenticatorFeedbackDialog");
        verify(dialog.visible);
        const firstHeight = dialog.implicitHeight;
        compare(findChild(dialog, "authenticatorDialogIcon").text, "error");
        compare(findChild(dialog, "authenticatorDialogTitle").text, "Error al leer el QR");
        compare(findChild(dialog, "authenticatorDialogMessage").text, "No se pudo leer el código QR.");
        verify(findChild(dialog, "authenticatorDialogAcknowledge").visible);
        verify(!findChild(dialog, "authenticatorDialogConfirm").visible);
        mouseClick(findChild(dialog, "authenticatorDialogAcknowledge"));
        compare(dismissedSpy.count, 1);
        compare(curtain.dialogVisible, false);
        curtain.dialogTitle = "Código añadido";
        curtain.dialogMessage = "Se guardó correctamente.";
        curtain.dialogIcon = "check_circle";
        curtain.dialogVisible = true;
        wait(20);
        compare(dialog.visible, true);
        compare(dialog.implicitHeight, firstHeight, "modal must retain its height after reopening");
    }

    function test_delete_confirmation_modal_offers_cancel_and_delete() {
        curtain.dialogTitle = "¿Borrar código?";
        curtain.dialogMessage = "Se eliminará Example · demo del almacén seguro.";
        curtain.dialogIcon = "delete";
        curtain.dialogDanger = true;
        curtain.dialogConfirm = true;
        curtain.dialogVisible = true;
        wait(30);
        const dialog = findChild(curtain, "authenticatorFeedbackDialog");
        verify(dialog.visible);
        compare(findChild(dialog, "authenticatorDialogIcon").text, "delete");
        verify(findChild(dialog, "authenticatorDialogCancel").visible);
        verify(findChild(dialog, "authenticatorDialogConfirm").visible);
        verify(!findChild(dialog, "authenticatorDialogAcknowledge").visible);
        mouseClick(findChild(dialog, "authenticatorDialogCancel"));
        compare(dismissedSpy.count, 1);
        compare(acceptedSpy.count, 0);
        compare(curtain.dialogVisible, false);

        curtain.dialogVisible = true;
        wait(20);
        const reopenedDialog = findChild(curtain, "authenticatorFeedbackDialog");
        mouseClick(findChild(reopenedDialog, "authenticatorDialogConfirm"));
        compare(acceptedSpy.count, 1);
        compare(curtain.dialogVisible, false);
    }

    function test_manual_entry_form_masks_secret_and_collects_parameters() {
        curtain.dialogTitle = "Añadir clave manualmente";
        curtain.dialogConfirm = true;
        curtain.dialogConfirmText = "Añadir";
        curtain.dialogVisible = true;
        wait(30);
        curtain.dialogMode = "manual";
        wait(30);
        compare(findChild(curtain, "authenticatorFeedbackDialog").currentHeight, 552,
            "dialog height must follow the form mode even after opening");
        const secret = findChild(curtain, "authenticatorManualSecret");
        const form = findChild(curtain, "authenticatorManualForm");
        const scroll = findChild(curtain, "authenticatorManualFormScroll");
        compare(form.width, 520, "manual fields should have a centered readable width");
        fuzzyCompare(form.x + form.width / 2, scroll.width / 2, 1);
        const algorithm = findChild(curtain, "authenticatorManualAlgorithm");
        const digits = findChild(curtain, "authenticatorManualDigits");
        const period = findChild(curtain, "authenticatorManualPeriod");
        compare(secret.echoMode, TextInput.Password);
        compare(algorithm.currentText, "SHA1");
        compare(digits.currentText, "6");
        compare(period.value, 30);
        curtain.manualIssuer = "Fixture";
        curtain.manualAccount = "demo";
        curtain.manualSecret = "JBSWY3DPEHPK3PXP";
        const data = curtain.dialogFormData();
        compare(data.issuer, "Fixture");
        compare(data.account, "demo");
        compare(data.secret, "JBSWY3DPEHPK3PXP");
        compare(data.digits, 6);
        compare(data.period, 30);
    }

    function test_encrypted_backup_password_is_masked() {
        curtain.dialogTitle = "Importar copia cifrada";
        curtain.dialogConfirm = true;
        curtain.dialogVisible = true;
        wait(30);
        curtain.dialogMode = "backup-password";
        wait(30);
        compare(findChild(curtain, "authenticatorFeedbackDialog").currentHeight, 420,
            "dialog height must expand when the password form is shown");
        const password = findChild(curtain, "authenticatorBackupPassword");
        compare(password.echoMode, TextInput.Password);
        curtain.backupPasswordInput = "synthetic-password";
        compare(curtain.dialogFormData().password, "synthetic-password");
    }

    function test_upward_drag_closes_once_and_tracks_edge() {
        const handle = findChild(curtain, "authenticatorCloseHandle");
        mouseDrag(handle, handle.width / 2, handle.height / 2, 0, -160);
        compare(dragSpy.count, 1);
        compare(dragSpy.signalArguments[0][0], true);
        compare(closeSpy.count, 1);
        verify(curtain.revealProgress < 1);
    }

    function test_short_or_downward_drag_returns_without_click() {
        const handle = findChild(curtain, "authenticatorCloseHandle");
        mouseDrag(handle, handle.width / 2, handle.height / 2, 0, -32);
        compare(dragSpy.count, 1);
        compare(dragSpy.signalArguments[0][0], false);
        compare(closeSpy.count, 0);
        compare(curtain.revealProgress, 1);
        dragSpy.clear();
        mouseDrag(handle, handle.width / 2, handle.height / 2, 0, 32);
        compare(dragSpy.count, 1);
        compare(dragSpy.signalArguments[0][0], false);
        compare(closeSpy.count, 0);
    }
}
