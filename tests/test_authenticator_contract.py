from __future__ import annotations

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


class AuthenticatorContractTest(unittest.TestCase):
    def test_authenticator_is_loaded_and_super_o_is_reserved(self) -> None:
        shell = read("config/quickshell/ii/shell.qml")
        states = read("config/quickshell/ii/GlobalStates.qml")
        keybinds = read("config/hypr/hyprland/keybinds.lua")
        self.assertIn("Authenticator {}", shell)
        self.assertIn("authenticatorOpen", states)
        self.assertIn('hl.bind("SUPER + O", hl.dsp.global("quickshell:authenticatorToggle")', keybinds)
        self.assertIn('hl.bind("SUPER + A", hl.dsp.global("quickshell:sidebarLeftToggle")', keybinds)

    def test_preserved_backend_uses_local_qr_and_secret_service(self) -> None:
        store = read("config/quickshell/ii/modules/common/authenticator/AuthenticatorStore.qml")
        script = read("config/quickshell/ii/scripts/authenticator.py")
        self.assertIn('"zbarimg"', script)
        self.assertIn('"secret-tool", "lookup"', store)
        self.assertIn('"otpauth://totp/"', store)

    def test_overlay_keeps_ipc_and_shortcut_without_management_actions(self) -> None:
        controller = read("config/quickshell/ii/modules/common/authenticator/Authenticator.qml")
        curtain = read("config/quickshell/ii/modules/common/authenticator/AuthenticatorCurtain.qml")
        self.assertIn('target: "authenticator"', controller)
        self.assertIn('name: "authenticatorToggle"', controller)
        self.assertIn('function toggle(): void', controller)
        self.assertIn('function close(): void', controller)
        self.assertIn('GlobalStates.toggleAuthenticator()', controller)
        for forbidden in ("secret-tool", "authenticator.py", "kdialog", "StyledTextInput", "captureQr", "exportAccounts", "GlobalFocusGrab"):
            with self.subTest(forbidden=forbidden):
                self.assertNotIn(forbidden, controller + curtain)

    def test_curtain_has_accounts_left_empty_right_and_centered_header(self) -> None:
        curtain = read("config/quickshell/ii/modules/common/authenticator/AuthenticatorCurtain.qml")
        self.assertIn('text: "heart_smile"', curtain)
        self.assertIn('text: "AUTENTICADOR"', curtain)
        self.assertIn('iconSize: Appearance.font.pixelSize.huge * 2', curtain)
        self.assertIn('font.weight: Font.ExtraBold', curtain)
        self.assertIn('font.variableAxes: Object.assign({}, Appearance.font.variableAxes.main, { "wght": 800 })', curtain)
        title_group = curtain.split('id: headerContent', 1)[1].split('id: body', 1)[0]
        self.assertIn('spacing: 2', title_group)
        self.assertIn('anchors.horizontalCenter: parent.horizontalCenter', curtain)
        self.assertIn('Accessible.name: "Cerrar autenticador"', curtain)
        self.assertIn('Keys.onEscapePressed:', curtain)
        self.assertIn('objectName: "authenticatorBody"', curtain)
        navigation = curtain.split('id: navigationPanel', 1)[1].split('id: contentPanel', 1)[0]
        self.assertIn('AuthenticatorAccounts {', navigation)
        self.assertIn('store: root.store', navigation)
        content = curtain.split('id: contentPanel', 1)[1].split('}', 1)[0]
        self.assertIn('Layout.fillWidth: true', content)
        self.assertIn('Layout.fillHeight: true', content)
        self.assertIn('AuthenticatorMethodGrid {', content)

    def test_body_is_split_twenty_eighty_after_the_gap(self) -> None:
        curtain = read("config/quickshell/ii/modules/common/authenticator/AuthenticatorCurtain.qml")
        self.assertIn('readonly property real availableWidth: Math.max(0, width - spacing)', curtain)
        navigation = curtain.split('id: navigationPanel', 1)[1].split('}', 1)[0]
        content = curtain.split('id: contentPanel', 1)[1].split('}', 1)[0]
        self.assertIn('Layout.preferredWidth: body.availableWidth * 0.2', navigation)
        self.assertIn('Layout.preferredWidth: body.availableWidth * 0.8', content)
        for panel in (navigation, content):
            self.assertIn('Layout.minimumWidth: 0', panel)

    def test_close_control_is_in_footer_not_header(self) -> None:
        curtain = read("config/quickshell/ii/modules/common/authenticator/AuthenticatorCurtain.qml")
        header = curtain.split('id: header', 1)[1].split('id: body', 1)[0]
        footer = curtain.split('id: footer', 1)[1]
        self.assertNotIn('Button {', header)
        self.assertNotIn('text: "close"', curtain)
        self.assertIn('id: closeHandle', footer)
        self.assertIn('anchors.centerIn: parent', footer)
        self.assertIn('implicitHeight: 48', footer)
        self.assertIn('Accessible.name: "Cerrar autenticador"', footer)
        self.assertIn('if (!root.suppressHandleClick) root.closeRequested()', footer)
        self.assertIn('parent.visualFocus', footer)
        self.assertIn('Keys.onEscapePressed:', curtain)

    def test_upward_drag_controls_curtain_and_suppresses_tap(self) -> None:
        curtain = read("config/quickshell/ii/modules/common/authenticator/AuthenticatorCurtain.qml")
        controller = read("config/quickshell/ii/modules/common/authenticator/Authenticator.qml")
        self.assertIn('DragHandler {', curtain)
        self.assertIn('target: null', curtain)
        self.assertIn('centroid.scenePosition.y', curtain)
        self.assertIn('root.upwardDrag >= root.closeDragDistance', curtain)
        self.assertIn('root.dragFinished(false)', curtain)
        self.assertIn('onDragStarted: root.beginDrag()', controller)
        self.assertIn('onDragMoved: distance => root.moveDrag(distance)', controller)
        self.assertIn('onDragFinished: dismiss => root.finishDrag(dismiss)', controller)
        self.assertIn('root.revealProgress = Math.max(0, root.gestureStartProgress - distance / travel)', controller)

    def test_accounts_view_is_secret_free_and_plain_text(self) -> None:
        view = read("config/quickshell/ii/modules/common/authenticator/AuthenticatorAccounts.qml")
        self.assertIn('ListView {', view)
        self.assertIn('model: root.entries', view)
        self.assertIn('AuthenticatorCountdown {', view)
        self.assertIn('Model.remainingFraction(row.modelData.period, root.now)', view)
        self.assertIn('anchors.centerIn: parent', view)
        self.assertIn('Aún no tienes códigos guardados.', view)
        self.assertIn('No se pudieron cargar los códigos.', view)
        self.assertIn('Text.PlainText', view)
        self.assertNotIn('.secret', view)
        self.assertNotIn('console.', view)
        self.assertLess(view.index('objectName: "authenticatorCode"'), view.index('objectName: "authenticatorAccountCaption"'))

    def test_store_view_lifecycle_validation_and_refresh_boundaries(self) -> None:
        store = read("config/quickshell/ii/modules/common/authenticator/AuthenticatorStore.qml")
        controller = read("config/quickshell/ii/modules/common/authenticator/Authenticator.qml")
        self.assertIn('store: AuthenticatorStore', controller)
        self.assertIn('Component.onCompleted: AuthenticatorStore.viewing = true', controller)
        self.assertIn('Component.onDestruction: AuthenticatorStore.viewing = false', controller)
        self.assertIn('running: root.loaded && root.viewing && !root.loadError', store)
        self.assertIn('Model.loadAccounts(loadOutput.text)', store)
        self.assertIn('Model.windowSignature(root.accounts, Date.now() / 1000) !== root.codeWindow', store)
        self.assertIn('Model.currentCode(entry, root.codes, root.codeGeneratedAt, Date.now() / 1000)', store)
        self.assertIn('root.codeRunningRevision === root.codeRevision', store)
        self.assertNotIn('console.', store)

    def test_copy_is_explicit_fresh_and_feedback_is_transient(self) -> None:
        view = read("config/quickshell/ii/modules/common/authenticator/AuthenticatorAccounts.qml")
        curtain = read("config/quickshell/ii/modules/common/authenticator/AuthenticatorCurtain.qml")
        controller = read("config/quickshell/ii/modules/common/authenticator/Authenticator.qml")
        self.assertIn('Qt.PointingHandCursor', view)
        click = view.split('onClicked: {', 1)[1].split('HoverHandler {', 1)[0]
        self.assertIn('root.store?.codeFor(row.modelData)', click)
        self.assertIn('root.copyRequested(code)', click)
        self.assertIn('copiedTimeout.restart()', click)
        self.assertIn('text: "Copiado"', view)
        self.assertIn('interval: 1200', view)
        self.assertIn('Math.max(accountCaption.implicitHeight, copiedCaption.implicitHeight)', view)
        self.assertIn('onCopyRequested: code => root.codeCopyRequested(code)', curtain)
        self.assertIn('Quickshell.clipboardText = code', controller)
        self.assertNotIn('execDetached', click)

    def test_authenticator_messages_use_modal_not_grid_inline_notice(self) -> None:
        controller = read("config/quickshell/ii/modules/common/authenticator/Authenticator.qml")
        curtain = read("config/quickshell/ii/modules/common/authenticator/AuthenticatorCurtain.qml")
        grid = read("config/quickshell/ii/modules/common/authenticator/AuthenticatorMethodGrid.qml")
        self.assertIn('WindowDialog {', curtain)
        self.assertIn('visible: root.dialogVisible', curtain)
        self.assertIn('backgroundHeight: root.dialogMode === "manual" ? Math.min(root.height - 48, 680)', curtain)
        self.assertIn('objectName: "authenticatorManualFormScroll"', curtain)
        self.assertIn('MaterialTextField {', curtain)
        self.assertIn('StyledComboBox {', curtain)
        self.assertIn('StyledSpinBox {', curtain)
        self.assertIn('onBackgroundHeightChanged:', read("config/quickshell/ii/modules/common/widgets/WindowDialog.qml"))
        self.assertIn(': root.dialogConfirm ? 280 : 250', curtain)
        for component in ("WindowDialogTitle", "WindowDialogParagraph", "MaterialSymbol", "DialogButton"):
            with self.subTest(component=component):
                self.assertIn(f'{component} {{', curtain)
        self.assertIn('textFormat: Text.PlainText', curtain)
        self.assertIn('property string dialogConfirmText: "Entendido"', curtain)
        self.assertIn('buttonText: root.dialogConfirmText', curtain)
        self.assertIn('anchors.horizontalCenter: parent.horizontalCenter', curtain)
        self.assertIn('onDialogAccepted: formData => root.acceptDialog(formData)', controller)
        self.assertIn('onDialogDismissed: root.dismissDialog()', controller)
        self.assertIn('root.showDialog(dialogTitle, dialogMessage, dialogIcon, dialogDanger, false)', controller)
        self.assertNotIn('authenticatorMethodNotice', grid)

    def test_right_click_delete_requires_two_button_confirmation(self) -> None:
        accounts = read("config/quickshell/ii/modules/common/authenticator/AuthenticatorAccounts.qml")
        curtain = read("config/quickshell/ii/modules/common/authenticator/AuthenticatorCurtain.qml")
        controller = read("config/quickshell/ii/modules/common/authenticator/Authenticator.qml")
        self.assertIn('acceptedButtons: Qt.RightButton', accounts)
        self.assertIn('root.deleteRequested(row.index,', accounts)
        self.assertIn('onDeleteRequested: (index, label) => root.deleteRequested(index, label)', curtain)
        self.assertIn('root.showDialogMode("¿Borrar código?"', controller)
        self.assertIn('buttonText: "Cancelar"', curtain)
        self.assertIn('buttonText: root.dialogConfirmText', curtain)
        self.assertIn('"delete", "Borrar", false', controller)
        self.assertIn('AuthenticatorStore.remove(root.pendingDeleteIndex)', controller)
        self.assertIn('root.dialogMode === "delete" && root.pendingDeleteIndex >= 0', controller)

    def test_right_panel_method_grid_has_six_options_with_qr_capture_active(self) -> None:
        grid = read("config/quickshell/ii/modules/common/authenticator/AuthenticatorMethodGrid.qml")
        curtain = read("config/quickshell/ii/modules/common/authenticator/AuthenticatorCurtain.qml")
        self.assertIn('columns: 3', grid)
        self.assertIn('rows: 2', grid)
        self.assertIn('Repeater {', grid)
        self.assertIn('MaterialSymbol {', grid)
        self.assertIn('horizontalAlignment: Text.AlignHCenter', grid)
        self.assertIn('Accessible.name: modelData.title + ". " + modelData.description', grid)
        self.assertIn('AuthenticatorMethodGrid {', curtain)
        titles = ("Capturar QR", "Abrir imagen", "Clave manual", "Pegar URI", "Migrar cuentas", "Importar copia")
        for title in titles:
            with self.subTest(title=title):
                self.assertIn(f'title: "{title}"', grid)
        self.assertIn('property bool available: root.storeReady && root.enabledMethods.indexOf(modelData.id) !== -1', grid)
        self.assertIn('storeReady: root.store?.loaded === true && root.store.loadError !== true', curtain)
        self.assertIn('enabledMethods: ["capture-screen-qr", "open-qr-image", "manual-secret", "paste-otp-uri", "google-migration", "encrypted-backup"]', curtain)
        self.assertIn('enabled: available', grid)
        self.assertIn('onClicked: root.methodSelected(modelData.id)', grid)

    def test_remaining_authentication_methods_use_validated_local_flows(self) -> None:
        controller = read("config/quickshell/ii/modules/common/authenticator/Authenticator.qml")
        curtain = read("config/quickshell/ii/modules/common/authenticator/AuthenticatorCurtain.qml")
        grid = read("config/quickshell/ii/modules/common/authenticator/AuthenticatorMethodGrid.qml")
        image_helper = read("config/quickshell/ii/scripts/authenticator-open-image-qr.sh")
        backup_helper = read("config/quickshell/ii/scripts/authenticator-read-backup.sh")
        for method_id, handler in (
            ("open-qr-image", "root.openQrImagePicker(false)"),
            ("manual-secret", "root.openManualForm()"),
            ("paste-otp-uri", "root.pasteOtpUri()"),
            ("google-migration", "root.openQrImagePicker(true)"),
            ("encrypted-backup", "root.openBackupPicker()"),
        ):
            with self.subTest(method=method_id):
                self.assertIn(f'method === "{method_id}"', controller)
                self.assertIn(handler, controller)
        self.assertIn('import QtQuick.Dialogs', controller)
        self.assertIn('fileMode: FileDialog.OpenFile', controller)
        self.assertIn('selectedFile.toLocalFile()', controller)
        self.assertIn('root.openFilePicker("qr-image")', controller)
        self.assertIn('root.openFilePicker("backup")', controller)
        self.assertIn('if (root.panelActive) GlobalStates.authenticatorOpen = false', controller)
        self.assertIn('Qt.callLater(() => root.openPendingFilePicker())', controller)
        self.assertIn('onRejected: root.restoreAuthenticatorAfterPicker()', controller)
        self.assertIn('root.restoreAuthenticatorAfterPicker();', controller)
        self.assertIn('root.pendingFilePicker = ""', controller)
        self.assertIn('GlobalStates.authenticatorOpen) {', controller)
        self.assertIn('authenticator-open-image-qr.sh', controller)
        self.assertIn('authenticator-read-backup.sh', controller)
        self.assertIn('file_size <= 26214400', image_helper)
        self.assertIn('width * height <= 50000000', image_helper)
        self.assertIn('file_size <= 5242880', backup_helper)
        self.assertIn('AuthenticatorStore.parseUri(uri)', controller)
        self.assertIn('echoMode: TextInput.Password', curtain)
        self.assertIn('write(JSON.stringify({ package: root.backupPackage, password: root.backupPassword }))', controller)
        self.assertIn('backupImportProcess.stdinEnabled = true', controller)
        self.assertIn('backupImportProcess.running = true', controller)
        self.assertIn('imageQrProcess.running = true', controller)
        self.assertIn('backupReadProcess.running = true', controller)
        self.assertNotIn('active: root.imageQrBusy', controller)
        self.assertNotIn('console.', controller)

    def test_remaining_authentication_methods_are_connected_and_local_only(self) -> None:
        controller = read("config/quickshell/ii/modules/common/authenticator/Authenticator.qml")
        curtain = read("config/quickshell/ii/modules/common/authenticator/AuthenticatorCurtain.qml")
        grid = read("config/quickshell/ii/modules/common/authenticator/AuthenticatorMethodGrid.qml")
        image_helper = read("config/quickshell/ii/scripts/authenticator-open-image-qr.sh")
        backup_helper = read("config/quickshell/ii/scripts/authenticator-read-backup.sh")

        self.assertIn('import QtQuick.Dialogs', controller)
        self.assertIn('function openQrImagePicker(migrationOnly: bool)', controller)
        self.assertIn('FileDialog.OpenFile', controller)
        self.assertIn('selectedFile.toLocalFile()', controller)
        self.assertIn('authenticator-open-image-qr.sh', controller)
        self.assertIn('authenticator-read-backup.sh', controller)
        self.assertIn('authenticator-capture-qr.sh', image_helper)
        self.assertIn('file_size <= 26214400', image_helper)
        self.assertIn('width * height <= 50000000', image_helper)
        self.assertIn('file_size <= 5242880', backup_helper)
        self.assertIn('function openManualForm()', controller)
        self.assertIn('AuthenticatorStore.validAccount(formData)', controller)
        self.assertIn('AuthenticatorStore.addMany([formData])', controller)
        self.assertIn('Quickshell.clipboardText || ""', controller)
        self.assertIn('AuthenticatorStore.parseUri(uri)', controller)
        self.assertIn('echoMode: TextInput.Password', curtain)
        self.assertIn('write(JSON.stringify({ package: root.backupPackage, password: root.backupPassword }))', controller)
        self.assertIn('AuthenticatorStore.script, "import"', controller)
        for method_id in ("open-qr-image", "manual-secret", "paste-otp-uri", "google-migration", "encrypted-backup"):
            with self.subTest(method_id=method_id):
                self.assertIn(f'method === "{method_id}"', controller)
        self.assertNotIn('console.', controller)

    def test_curtain_reveals_fixed_size_content_and_preserves_exit(self) -> None:
        controller = read("config/quickshell/ii/modules/common/authenticator/Authenticator.qml")
        curtain = read("config/quickshell/ii/modules/common/authenticator/AuthenticatorCurtain.qml")
        self.assertIn('active: root.panelActive', controller)
        self.assertNotIn('active: GlobalStates.authenticatorOpen', controller)
        self.assertIn('alwaysRunToEnd: false', controller)
        self.assertIn('revealAnimation.from = root.revealProgress', controller)
        self.assertIn('Appearance.animation.elementMoveEnter', controller)
        self.assertIn('Appearance.animation.elementMoveExit', controller)
        self.assertIn('clip: true', curtain)
        self.assertIn('height: root.height', curtain)
        self.assertIn('root.revealProgress', curtain)

    def test_layout_diagnostic_colors_are_removed(self) -> None:
        curtain = read("config/quickshell/ii/modules/common/authenticator/AuthenticatorCurtain.qml")
        grid = read("config/quickshell/ii/modules/common/authenticator/AuthenticatorMethodGrid.qml")
        for color in ("#f6d77a", "#B5ABDE", "#A4B29A", "#99BFD5", "#24A4B29A", "#2499BFD5"):
            with self.subTest(color=color):
                self.assertNotIn(color, curtain + grid)
        self.assertNotIn('border.color: "#719BB2"', grid)
        self.assertIn(': Appearance.colors.colLayer1', grid)
        self.assertIn('color: "transparent"', curtain)

    def test_region_selector_uses_private_return_path_for_qr_capture(self) -> None:
        region_selector = read("config/quickshell/ii/modules/ii/regionSelector/RegionSelector.qml")
        region_selection = read("config/quickshell/ii/modules/ii/regionSelector/RegionSelection.qml")
        authenticator = read("config/quickshell/ii/modules/common/authenticator/Authenticator.qml")
        capture_script = read("config/quickshell/ii/scripts/authenticator-capture-qr.sh")
        self.assertIn('function authenticatorQr()', region_selector)
        self.assertIn('Quickshell.screens.filter(screen => screen.name === GlobalStates.authenticatorQrScreenName)', region_selector)
        self.assertIn('function authenticatorQr()', region_selector.split('IpcHandler {', 1)[1])
        self.assertIn('SnipAction.AuthenticatorCaptureQr', region_selection)
        self.assertIn('authenticator-capture-qr.sh', region_selection)
        self.assertIn('authenticatorQrCaptureRevision += 1', region_selection)
        self.assertIn('onRegionSelectorOpenChanged()', authenticator)
        self.assertLess(authenticator.index('Date.now() - root.qrCaptureStartedAt >= 60000'), authenticator.index('if (GlobalStates.regionSelectorOpen)', authenticator.index('id: qrCaptureWatchdog')))
        self.assertIn('root.abortQrCapture("Captura cancelada al bloquear la sesión.")', authenticator)
        abort = authenticator.split('function abortQrCapture', 1)[1].split('onSelectedScreenChanged', 1)[0]
        self.assertLess(abort.index('root.qrCaptureActive = false'), abort.index('GlobalStates.regionSelectorOpen = false'))
        self.assertIn('AuthenticatorStore.parseUri(value)', authenticator)
        self.assertIn('AuthenticatorStore.addMany(accounts)', authenticator)
        self.assertIn('GlobalStates.authenticatorQrPayload = ""', authenticator)
        self.assertIn('trap cleanup EXIT', capture_script)
        self.assertIn('timeout 10s', capture_script)
        screenshot_helper = read("config/quickshell/ii/scripts/authenticator-private-screenshot.sh")
        self.assertIn('umask 077', screenshot_helper)
        self.assertIn('if [[ -e "$image" ]]; then', screenshot_helper)
        self.assertIn('chmod 600 -- "$image"', screenshot_helper)
        self.assertIn('root.finishAuthenticatorQr("error", "")', region_selection)
        # The recording monitor must not dismiss the selector for non-recording
        # Post-phase actions (it cancelled the QR scan right after selecting).
        self.assertIn('running: root.isRecording && root.phase === RegionSelection.Phase.Post && root.visible', region_selection)
        self.assertNotIn('wl-copy', capture_script)
        capture_branch = region_selection.split('const width = Math.round(root.regionWidth * root.monitorScale);', 1)[1].split('// Adjust action', 1)[0]
        self.assertNotIn('console.', authenticator + capture_branch)

    def test_region_selection_imports_shell_root_and_cursor_guide_handles_capture(self) -> None:
        directory = ROOT / "config/quickshell/ii/modules/ii/regionSelector"
        for path in sorted(directory.glob("*.qml")):
            text = path.read_text(encoding="utf-8")
            if "GlobalStates." not in text:
                continue
            with self.subTest(file=path.name):
                self.assertIn("import qs", [line.strip() for line in text.splitlines()])
        cursor_guide = read("config/quickshell/ii/modules/ii/regionSelector/CursorGuide.qml")
        self.assertEqual(cursor_guide.count("case RegionSelection.SnipAction.AuthenticatorCaptureQr:"), 2)
        self.assertIn('return "qr_code_scanner";', cursor_guide)

    def test_expansion_origin_and_motion_do_not_snap(self) -> None:
        controller = read("config/quickshell/ii/modules/common/authenticator/Authenticator.qml")
        curtain = read("config/quickshell/ii/modules/common/authenticator/AuthenticatorCurtain.qml")
        self.assertIn('Appearance.sizes.barHeight', curtain)
        self.assertIn('root.collapsedHeight + (root.height - root.collapsedHeight) * root.expansion', curtain)
        self.assertIn('opacity: Math.min(1, root.expansion * 12)', curtain)
        self.assertIn('Easing.InOutCubic', controller)
        self.assertIn('Math.max(160, fullDuration *', controller)
        self.assertNotIn('revealAnimation.easing.bezierCurve', controller)

    def test_overlay_monitor_focus_and_emergency_teardown_contract(self) -> None:
        controller = read("config/quickshell/ii/modules/common/authenticator/Authenticator.qml")
        states = read("config/quickshell/ii/GlobalStates.qml")
        self.assertIn('screen: root.selectedScreen', controller)
        self.assertIn('WlrLayer.Overlay', controller)
        self.assertIn('WlrKeyboardFocus.Exclusive', controller)
        self.assertIn('ExclusionMode.Ignore', controller)
        self.assertIn('onScreenLockedChanged()', controller)
        self.assertIn('onSelectedScreenChanged:', controller)
        self.assertIn('closeImmediately()', controller)
        self.assertIn('Hyprland.focusedMonitor?.name', states)
        self.assertIn('if (!root.authenticatorPresented)', states)

    def test_bar_heart_has_separate_button_and_retains_layout_slot(self) -> None:
        bar = read("config/quickshell/ii/modules/ii/bar/BarContent.qml")
        self.assertIn('implicitWidth: heartButton.implicitWidth', bar)
        self.assertIn('implicitHeight: heartButton.implicitHeight', bar)
        button = bar.split('id: heartButton', 1)[1].split('BatteryIndicator {', 1)[0]
        self.assertIn('GlobalStates.openAuthenticator(root.screen?.name ?? "")', button)
        self.assertIn('!GlobalStates.authenticatorOpen && !GlobalStates.authenticatorPresented', button)
        self.assertNotIn('sidebarRightOpen', button)
        self.assertIn('GlobalStates.sidebarRightOpen = !GlobalStates.sidebarRightOpen', bar)

    def test_installer_supplies_system_python_and_qr_dependencies(self) -> None:
        installer = read("scripts/install-deps.sh")
        store = read("config/quickshell/ii/modules/common/authenticator/AuthenticatorStore.qml")
        self.assertIn('python: "/usr/bin/python"', store)
        for package in ("python-protobuf", "python-cryptography", "zbar", "libsecret"):
            self.assertIn(package, installer)


if __name__ == "__main__":
    unittest.main()
