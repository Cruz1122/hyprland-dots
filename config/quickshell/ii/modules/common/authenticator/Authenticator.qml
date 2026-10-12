import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.authenticator
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: root
    property string message: ""
    property bool editing: false
    property string uriInput: ""
    property string filePath: ""
    property string exportPassword: ""
    property string exportPath: ""
    property string importPassword: ""
    property var exportAccounts: []
    property bool adding: false
    property string copyPayload: ""

    function notify(value) { root.message = value; messageTimer.restart() }
    function beginAdding() { root.adding = true; editorTimer.restart() }
    property bool captureSeen: false
    property int captureWaitTicks: 0
    property string exportOutput: ""

    function addUri(uri) {
        const account = AuthenticatorStore.parseUri(uri)
        if (!account) { root.notify("QR o URI TOTP no válido"); return }
        AuthenticatorStore.add(account)
        root.uriInput = ""
        root.adding = false
        root.notify("Añadido")
    }
    function consumeQrOutput(value) {
        const output = String(value).trim()
        if (!output) return
        if (output.startsWith("[")) AuthenticatorStore.addMany(JSON.parse(output))
        else output.split("\n").filter(line => line.trim()).forEach(line => root.addUri(line))
    }
    function captureQr() {
        root.notify("Selecciona el QR")
        // The region selector needs the keyboard/mouse focus. Do not leave the
        // full-screen authenticator layer above it while selecting the region.
        GlobalStates.authenticatorOpen = false
        root.captureSeen = false
        root.captureWaitTicks = 0
        captureProcess.running = true
    }
    function openFile() { GlobalStates.authenticatorOpen = false; fileProcess.running = true }
    function exportGroup() { root.exportAccounts = AuthenticatorStore.accounts.slice(); GlobalStates.authenticatorOpen = false; passwordProcess.running = true }
    function exportSingle(account) { root.exportAccounts = [account]; GlobalStates.authenticatorOpen = false; passwordProcess.running = true }
    function importGroup() { GlobalStates.authenticatorOpen = false; importFileProcess.running = true }

    Process {
        id: captureProcess
        command: ["qs", "-c", "ii", "ipc", "call", "region", "screenshot"]
        onExited: captureTimer.restart()
    }
    Timer {
        id: captureTimer
        interval: 100
        repeat: true
        onTriggered: {
            root.captureWaitTicks += 1
            if (!root.captureSeen && GlobalStates.regionSelectorOpen) root.captureSeen = true
            if (root.captureSeen && !GlobalStates.regionSelectorOpen) {
                stop()
                qrProcess.running = true
            } else if (root.captureWaitTicks >= 600) {
                stop()
                root.notify("Captura cancelada o agotó el tiempo")
                GlobalStates.authenticatorOpen = true
            }
        }
    }
    Process {
        id: qrProcess
        command: ["bash", "-c", `set -o pipefail; mkdir -p /tmp/quickshell/media/screenshot; trap 'rm -f /tmp/quickshell/media/screenshot/authenticator-qr.png' EXIT; wl-paste --type image/png > /tmp/quickshell/media/screenshot/authenticator-qr.png && ${AuthenticatorStore.python} ${AuthenticatorStore.script} qr /tmp/quickshell/media/screenshot/authenticator-qr.png`]
        stdout: StdioCollector { onStreamFinished: { root.consumeQrOutput(text); GlobalStates.authenticatorOpen = true } }
        onExited: if (exitCode !== 0) root.notify("No se detectó un QR TOTP")
    }
    Process {
        id: fileProcess
        command: ["kdialog", "--getopenfilename", "", "*.png *.jpg *.jpeg *.webp"]
        stdout: StdioCollector { onStreamFinished: { root.filePath = text.trim(); if (root.filePath) fileQrProcess.running = true } }
    }
    Process {
        id: fileQrProcess
        command: [AuthenticatorStore.python, AuthenticatorStore.script, "qr", root.filePath]
        stdout: StdioCollector { onStreamFinished: { root.consumeQrOutput(text); GlobalStates.authenticatorOpen = true } }
        onExited: if (exitCode !== 0) root.notify("No se detectó un QR TOTP")
    }
    Process {
        id: importFileProcess
        command: ["kdialog", "--getopenfilename", "", "*.ii-auth"]
        stdout: StdioCollector { onStreamFinished: { root.filePath = text.trim(); if (root.filePath) { importReadProcess.running = true } } }
    }
    Process {
        id: importReadProcess
        command: ["cat", root.filePath]
        stdout: StdioCollector { onStreamFinished: { importPackage = text; importPasswordProcess.running = true } }
    }
    property string importPackage: ""
    Process {
        id: importPasswordProcess
        command: ["kdialog", "--password", "Contraseña del grupo"]
        stdout: StdioCollector { onStreamFinished: { root.importPassword = text.replace(/\r?\n$/, ""); importProcess.stdinEnabled = true; importProcess.running = true } }
    }
    Process {
        id: importProcess
        command: [AuthenticatorStore.python, AuthenticatorStore.script, "import"]
        onRunningChanged: {
            if (running) {
                write(JSON.stringify({package: root.importPackage, password: root.importPassword}))
                stdinEnabled = false
            }
        }
        stdout: StdioCollector {
            onStreamFinished: {
                try { AuthenticatorStore.addMany(JSON.parse(text)); root.importPassword = ""; root.notify("Grupo importado"); GlobalStates.authenticatorOpen = true }
                catch (error) { root.importPassword = ""; root.notify("Exportación inválida o contraseña incorrecta") }
            }
        }
    }
    Process {
        id: passwordProcess
        command: ["kdialog", "--password", "Contraseña para exportar el grupo"]
        stdout: StdioCollector { onStreamFinished: { root.exportPassword = text.replace(/\r?\n$/, ""); if (root.exportPassword) saveProcess.running = true } }
    }
    Process {
        id: saveProcess
        command: ["kdialog", "--getsavefilename", "", "authenticator.ii-auth"]
        stdout: StdioCollector { onStreamFinished: { root.exportPath = text.trim(); if (root.exportPath) exportProcess.running = true } }
    }
    Process {
        id: exportProcess
        command: [AuthenticatorStore.python, AuthenticatorStore.script, "export"]
        onRunningChanged: {
            if (running) {
                stdinEnabled = true
                write(JSON.stringify({accounts: root.exportAccounts, password: root.exportPassword}))
                stdinEnabled = false
            }
        }
        stdout: StdioCollector { onStreamFinished: { root.exportOutput = text.trim() } }
        onExited: {
            if (exitCode !== 0 || !root.exportOutput) {
                root.notify("No se pudo exportar el grupo")
            } else {
                exportFile.path = root.exportPath
                exportFile.setText(root.exportOutput)
                root.exportPassword = ""
                root.exportOutput = ""
                root.notify("Grupo exportado")
                GlobalStates.authenticatorOpen = true
            }
        }
    }
    FileView { id: exportFile; path: root.exportPath }

    Loader {
        active: GlobalStates.authenticatorOpen
        sourceComponent: PanelWindow {
            id: panel
            visible: true
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "quickshell:authenticator"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
            anchors { top: true; bottom: true; left: true; right: true }
            Rectangle { anchors.fill: parent; color: Appearance.colors.colLayer0; opacity: 0.28 }
            MouseArea { anchors.fill: parent; z: 0; onClicked: GlobalStates.authenticatorOpen = false }
            Component.onCompleted: GlobalFocusGrab.addDismissable(panel)
            Component.onDestruction: GlobalFocusGrab.removeDismissable(panel)
            Connections { target: GlobalFocusGrab; function onDismissed() { GlobalStates.authenticatorOpen = false } }

            Rectangle {
                id: content
                focus: true
                Component.onCompleted: forceActiveFocus()
                anchors.centerIn: parent
                width: Math.min(parent.width - 32, 520)
                height: Math.min(parent.height - 32, 620)
                radius: Appearance.rounding.large
                color: Appearance.colors.colLayer0
                border.color: Appearance.colors.colLayer0Border
                border.width: 1

                ColumnLayout {
                    anchors.fill: parent; anchors.margins: 18; spacing: 10
                    RowLayout {
                        Layout.fillWidth: true
                        StyledText { text: "Authenticator"; font.pixelSize: Appearance.font.pixelSize.large; font.weight: Font.DemiBold; Layout.fillWidth: true }
                        IconToolbarButton { text: "add"; implicitWidth: 38; colBackground: Appearance.colors.colLayer2; colBackgroundHover: Appearance.colors.colLayer2Hover; onClicked: root.beginAdding() }
                        IconToolbarButton { text: "close"; implicitWidth: 38; colBackground: Appearance.colors.colLayer2; colBackgroundHover: Appearance.colors.colLayer2Hover; onClicked: GlobalStates.authenticatorOpen = false }
                    }
                    StyledText { visible: root.message.length > 0; text: root.message; color: Appearance.colors.colPrimary; Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter }
                    ColumnLayout {
                        visible: root.adding; Layout.fillWidth: true; spacing: 6
                        StyledText { text: "Añadir código"; font.weight: Font.DemiBold; Layout.fillWidth: true }
                        Rectangle {
                            Layout.fillWidth: true; implicitHeight: 42; radius: Appearance.rounding.small
                            color: Appearance.colors.colLayer1; border.color: uriField.activeFocus ? Appearance.colors.colPrimary : Appearance.colors.colLayer0Border; border.width: 1
                            StyledTextInput { id: uriField; anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 12; focus: root.adding; text: root.uriInput; onTextChanged: root.uriInput = text; Keys.onReturnPressed: root.addUri(text) }
                        }
                        GridLayout {
                            Layout.fillWidth: true
                            columns: 2; rowSpacing: 6; columnSpacing: 6
                            IconAndTextToolbarButton { text: "Añadir URI"; iconText: "add_link"; Layout.fillWidth: true; colBackground: Appearance.colors.colLayer2; colBackgroundHover: Appearance.colors.colLayer2Hover; onClicked: root.addUri(uriField.text) }
                            IconAndTextToolbarButton { text: "Capturar QR"; iconText: "qr_code_scanner"; Layout.fillWidth: true; colBackground: Appearance.colors.colLayer2; colBackgroundHover: Appearance.colors.colLayer2Hover; onClicked: root.captureQr() }
                            IconAndTextToolbarButton { text: "Abrir imagen"; iconText: "image"; Layout.fillWidth: true; colBackground: Appearance.colors.colLayer2; colBackgroundHover: Appearance.colors.colLayer2Hover; onClicked: root.openFile() }
                            IconAndTextToolbarButton { text: "Importar grupo"; iconText: "file_upload"; Layout.fillWidth: true; colBackground: Appearance.colors.colLayer2; colBackgroundHover: Appearance.colors.colLayer2Hover; onClicked: root.importGroup() }
                        }
                    }
                    ListView {
                        id: list; Layout.fillWidth: true; Layout.fillHeight: true; clip: true; spacing: 6
                        model: AuthenticatorStore.accounts
                        delegate: Rectangle {
                            required property var modelData; required property int index
                            width: list.width; height: 82; radius: Appearance.rounding.small; color: Appearance.colors.colLayer1
                            RowLayout {
                                anchors.fill: parent; anchors.margins: 12
                                ColumnLayout { Layout.fillWidth: true; spacing: 0
                                    StyledText { text: modelData.issuer || "TOTP"; font.pixelSize: Appearance.font.pixelSize.small }
                                    StyledText { text: modelData.account; color: Appearance.colors.colSubtext; font.pixelSize: Appearance.font.pixelSize.smaller }
                                }
                                ColumnLayout { spacing: 0
                                    StyledText { text: AuthenticatorStore.codes[AuthenticatorStore.key(modelData)] || "------"; font.pixelSize: Appearance.font.pixelSize.large; font.family: Appearance.font.family.numbers }
                                    StyledText { text: `${AuthenticatorStore.secondsRemaining(modelData)} s`; color: Appearance.colors.colSubtext; Layout.alignment: Qt.AlignRight }
                                }
                                IconToolbarButton { text: "content_copy"; implicitWidth: 36; colBackground: Appearance.colors.colLayer2; colBackgroundHover: Appearance.colors.colLayer2Hover; onClicked: { root.copyPayload = AuthenticatorStore.codes[AuthenticatorStore.key(modelData)] || ""; copyProcess.running = true; root.notify("Código copiado") } }
                                IconToolbarButton { text: "file_download"; implicitWidth: 36; colBackground: Appearance.colors.colLayer2; colBackgroundHover: Appearance.colors.colLayer2Hover; onClicked: root.exportSingle(modelData) }
                                IconToolbarButton { text: "delete"; implicitWidth: 36; colBackground: Appearance.colors.colLayer2; colBackgroundHover: Appearance.colors.colErrorContainerHover; onClicked: AuthenticatorStore.remove(index) }
                            }
                        }
                        StyledText { anchors.centerIn: parent; visible: list.count === 0; text: "Añade tu primer código"; color: Appearance.colors.colSubtext }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        IconAndTextToolbarButton { text: "Importar"; iconText: "file_upload"; Layout.fillWidth: true; colBackground: Appearance.colors.colLayer2; colBackgroundHover: Appearance.colors.colLayer2Hover; onClicked: root.beginAdding() }
                        IconAndTextToolbarButton { text: "Exportar"; iconText: "file_download"; Layout.fillWidth: true; colBackground: Appearance.colors.colLayer2; colBackgroundHover: Appearance.colors.colLayer2Hover; onClicked: root.exportGroup() }
                    }
                }
                Keys.onPressed: event => { if (event.key === Qt.Key_Escape) GlobalStates.authenticatorOpen = false }
            }
        }
    }

    Timer { id: messageTimer; interval: 2800; repeat: false; onTriggered: root.message = "" }
    Timer { id: editorTimer; interval: 12000; repeat: false; onTriggered: root.adding = false }
    Process {
        id: copyProcess
        command: ["wl-copy", "--paste-once"]
        onRunningChanged: if (running) { stdinEnabled = true; write(root.copyPayload); stdinEnabled = false }
    }

    IpcHandler {
        target: "authenticator"
        function toggle(): void {
            GlobalStates.authenticatorOpen = !GlobalStates.authenticatorOpen
        }
        function close(): void {
            GlobalStates.authenticatorOpen = false
        }
    }

    GlobalShortcut {
        name: "authenticatorToggle"
        description: "Toggle authenticator"
        onPressed: GlobalStates.authenticatorOpen = !GlobalStates.authenticatorOpen
    }
}
